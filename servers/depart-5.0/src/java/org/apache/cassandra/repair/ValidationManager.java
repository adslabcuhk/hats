/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.cassandra.repair;

import java.io.File;
import java.io.IOException;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.common.collect.Maps;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.db.ColumnFamilyStore;
import org.apache.cassandra.db.compaction.CompactionInterruptedException;
import org.apache.cassandra.db.rows.UnfilteredRowIterator;
import org.apache.cassandra.dht.Range;
import org.apache.cassandra.dht.Token;
import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.metrics.TableMetrics;
import org.apache.cassandra.metrics.TopPartitionTracker;
import org.apache.cassandra.repair.state.ValidationState;
import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.utils.Clock;
import org.apache.cassandra.utils.FBUtilities;
import org.apache.cassandra.utils.MerkleTree;
import org.apache.cassandra.utils.MerkleTrees;
import org.iq80.twoLayerLog.Options;
import org.iq80.twoLayerLog.impl.DbImpl;

public class ValidationManager implements IValidationManager
{
    private static final Logger logger = LoggerFactory.getLogger(ValidationManager.class);

    public static final ValidationManager instance = new ValidationManager();

    private ValidationManager() {}

    private static MerkleTrees createMerkleTrees(ValidationPartitionIterator validationIterator, Collection<Range<Token>> ranges, ColumnFamilyStore cfs)
    {
        MerkleTrees trees = new MerkleTrees(cfs.getPartitioner());
        long allPartitions = validationIterator.estimatedPartitions();
        Map<Range<Token>, Long> rangePartitionCounts = validationIterator.getRangePartitionCounts();

        // The repair coordinator must hold RF trees in memory at once, so a given validation compaction can only
        // use 1 / RF of the allowed space.
        long availableBytes = (DatabaseDescriptor.getRepairSessionSpaceInMiB() * 1048576) /
                              cfs.keyspace.getReplicationStrategy().getReplicationFactor().allReplicas;

        for (Range<Token> range : ranges)
        {
            long numPartitions = rangePartitionCounts.get(range);
            double rangeOwningRatio = allPartitions > 0 ? (double)numPartitions / allPartitions : 0;
            // determine max tree depth proportional to range size to avoid blowing up memory with multiple tress,
            // capping at a depth that does not exceed our memory budget (CASSANDRA-11390, CASSANDRA-14096)
            int rangeAvailableBytes = Math.max(1, (int) (rangeOwningRatio * availableBytes));
            // Try to estimate max tree depth that fits the space budget assuming hashes of 256 bits = 32 bytes
            // note that estimatedMaxDepthForBytes cannot return a number lower than 1
            int estimatedMaxDepth = MerkleTree.estimatedMaxDepthForBytes(cfs.getPartitioner(), rangeAvailableBytes, 32);
            int maxDepth = rangeOwningRatio > 0
                           ? Math.min(estimatedMaxDepth, DatabaseDescriptor.getRepairSessionMaxTreeDepth())
                           : 0;
            // determine tree depth from number of partitions, capping at max tree depth (CASSANDRA-5263)
            int depth = numPartitions > 0 ? (int) Math.min(Math.ceil(Math.log(numPartitions) / Math.log(2)), maxDepth) : 0;
            trees.addMerkleTree((int) Math.pow(2, depth), range);
        }
        if (logger.isDebugEnabled())
        {
            // MT serialize may take time
            logger.debug("Created {} merkle trees with merkle trees size {}, {} partitions, {} bytes", trees.ranges().size(), trees.size(), allPartitions, MerkleTrees.serializer.serializedSize(trees, 0));
        }

        return trees;
    }



    private static MerkleTrees createMerkleTreesForReplica(Collection<Range<Token>> ranges, ColumnFamilyStore cfs)
    {
        MerkleTrees tree = new MerkleTrees(cfs.getPartitioner());
        long allPartitions = 0;
        Map<Range<Token>, Long> rangePartitionCounts = Maps.newHashMapWithExpectedSize(ranges.size());
        InetAddress LOCAL = FBUtilities.getJustBroadcastAddress();
        for (Range<Token> range : ranges)
        {
            long numPartitions = 0;
            /////////////////////////////////////////
            List<InetAddress> ep = StorageService.instance.getNaturalEndpoints(cfs.keyspace.getName(), range.right);
            if (!ep.get(0).equals(LOCAL)) {//the range is stored in replica copy
                byte ip[] = ep.get(0).getAddress();  
                int NodeID = (int)ip[3];
                Token rightBound = StorageService.instance.getBoundToken(range.right);
                int rangeGroupRowNumber = StorageService.instance.getRangeGroupRowNumber(NodeID, rightBound);
                numPartitions += rangeGroupRowNumber;
                logger.debug("in createMerkleTreesForReplica, NodeID:{}, range.left:{}, range.right:{}, rightBound:{}, rangeGroupRowNumber:{}, allPartitions:{}", NodeID, range.left, range.right, rightBound, rangeGroupRowNumber, allPartitions);

            }
            //logger.debug("before rangePartitionCounts.put, range.left:{}, range.right:{}, numPartitions:{}", range.left, range.right, numPartitions);
            rangePartitionCounts.put(range, numPartitions);
            allPartitions += numPartitions;
        }
        logger.debug("in createMerkleTreesForReplica, allPartitions:{}", allPartitions);

        for (Range<Token> range : ranges)
        {
            long numPartitions = rangePartitionCounts.get(range);
            double rangeOwningRatio = allPartitions > 0 ? (double)numPartitions / allPartitions : 0;
            // determine max tree depth proportional to range size to avoid blowing up memory with multiple tress,
            // capping at 20 to prevent large tree (CASSANDRA-11390)
            int maxDepth = rangeOwningRatio > 0 ? (int) Math.floor(20 - Math.log(1 / rangeOwningRatio) / Math.log(2)) : 0;
            // determine tree depth from number of partitions, capping at max tree depth (CASSANDRA-5263)
            int depth = numPartitions > 0 ? (int) Math.min(Math.ceil(Math.log(numPartitions) / Math.log(2)), maxDepth) : 0;
            tree.addMerkleTree((int) Math.pow(2, depth), range);
        }
        if (logger.isDebugEnabled())
        {
            // MT serialize may take time
            logger.debug("Created {} merkle trees with merkle trees size {}, {} partitions, {} bytes", tree.ranges().size(), tree.size(), allPartitions, MerkleTrees.serializer.serializedSize(tree, 0));
        }

        return tree;
    }



    private static ValidationPartitionIterator getValidationIterator(TableRepairManager repairManager, Validator validator, TopPartitionTracker.Collector topPartitionCollector) throws IOException, NoSuchRepairSessionException
    {
        RepairJobDesc desc = validator.desc;
        return repairManager.getValidationIterator(desc.ranges, desc.parentSessionId, desc.sessionId, validator.isIncremental, validator.nowInSec, topPartitionCollector);
    }

    /**
     * Performs a readonly "compaction" of all sstables in order to validate complete rows,
     * but without writing the merge result
     */
    public static void doValidation(ColumnFamilyStore cfs, Validator validator) throws IOException, NoSuchRepairSessionException
    {
        StorageService.instance.duringRepair = true;
        long beginTime = System.currentTimeMillis();//////
        SharedContext ctx = validator.ctx;
        Clock clock = ctx.clock();
        // this isn't meant to be race-proof, because it's not -- it won't cause bugs for a CFS to be dropped
        // mid-validation, or to attempt to validate a droped CFS.  this is just a best effort to avoid useless work,
        // particularly in the scenario where a validation is submitted before the drop, and there are compactions
        // started prior to the drop keeping some sstables alive.  Since validationCompaction can run
        // concurrently with other compactions, it would otherwise go ahead and scan those again.
        ValidationState state = validator.state;
        if (!cfs.isValid())
        {
            state.phase.skip(String.format("Table %s is not valid", cfs));
            return;
        }



        ///////////////////////////////////////////////////
        Options options = new Options();
        options.createIfMissing(true);
        Set<InetAddressAndPort> liveHosts = Gossiper.instance.getLiveMembers();
        try {
            String DBname = "data/replicatedData";
            File file = new File(DBname);
            if(!file.exists()){
                //StorageService.instance.db = factory.open(file, options);
                StorageService.instance.db = new DbImpl(options, file, null);
            }
            //db.close();
        } catch(Throwable e){
                logger.debug("open twoLayerLog failed!!");
        }
        InetAddressAndPort LOCAL = FBUtilities.getBroadcastAddressAndPort();
        for (InetAddressAndPort host : liveHosts){///
            if (!host.equals(LOCAL)) {          
                Collection<Token> nodeToken = StorageService.instance.getTokenMetadata().getTokens(host);
                //logger.debug("nodeIP:{}, nodeToken size:{}, nodeToken:{}", host, nodeToken.size(), nodeToken);
                List<String> strTokensList = new ArrayList<String>();
                for(Token tk: nodeToken){
                    String strToken = StorageService.instance.getTokenFactory().toString(tk);//////
                    strTokensList.add(strToken);
                    //logger.debug("strToken size:{}, strToken:{}", strTokensList.size(), strToken);
                }
                try{
                    byte ip[] = host.getAddress().getAddress();  
                    int NodeID = (int)ip[3];
                    StorageService.instance.db.initializeReplicaDir(NodeID, strTokensList, cfs.keyspace.getName());
                } catch(Throwable e){
                    logger.debug("create replicaDir failed!!");
                }
            }
        }
        ////////////////////////////////////////////////////
        Collection<Range<Token>> validatorRanges = validator.desc.ranges;
        Collection<Range<Token>> mainRanges = new ArrayList<>();
        Collection<Range<Token>> replicaRanges = new ArrayList<>();
        for(Range<Token> curRang: validatorRanges){
            List<InetAddress> ep = StorageService.instance.getNaturalEndpoints(cfs.keyspace.getName(), curRang.right);
            if (!ep.get(0).equals(LOCAL)) {//the range is stored in replica copy
                replicaRanges.add(curRang);
            }else{
                mainRanges.add(curRang);
            }
        }
        logger.debug("validatorRanges size:{}, mainRanges size:{}, replicaRanges size:{}", validatorRanges.size(), mainRanges.size(), replicaRanges.size());
///////////////////////////////////////////////////////////

        TopPartitionTracker.Collector topPartitionCollector = null;

        if(mainRanges.size()>0){
            if (cfs.topPartitions != null && DatabaseDescriptor.topPartitionsEnabled() && isTopPartitionSupported(validator))
                topPartitionCollector = new TopPartitionTracker.Collector(validator.desc.ranges);

            // Create Merkle trees suitable to hold estimated partitions for the given ranges.
            // We blindly assume that a partition is evenly distributed on all sstables for now.
            long start = clock.nanoTime();
            try (ValidationPartitionIterator vi = getValidationIterator(ctx.repairManager(cfs), validator, topPartitionCollector))
            {
                state.phase.start(vi.estimatedPartitions(), vi.getEstimatedBytes());
                MerkleTrees trees = createMerkleTrees(vi, validator.desc.ranges, cfs);
                // validate the CF as we iterate over it
                validator.prepare(cfs, trees, topPartitionCollector);
                while (vi.hasNext())
                {
                    try (UnfilteredRowIterator partition = vi.next())
                    {
                        validator.add(partition);
                        state.partitionsProcessed++;
                        state.bytesRead = vi.getBytesRead();
                        if (state.partitionsProcessed % 1024 == 0) // update every so often
                            state.updated();
                    }
                }
                validator.complete();
            }
            finally
            {
                cfs.metric.bytesValidated.update(state.estimatedTotalBytes);
                cfs.metric.partitionsValidated.update(state.partitionsProcessed);
                if (topPartitionCollector != null)
                    cfs.topPartitions.merge(topPartitionCollector);
            }
            if (logger.isDebugEnabled())
            {
                long duration = TimeUnit.NANOSECONDS.toMillis(clock.nanoTime() - start);
                logger.debug("Validation of {} partitions (~{}) finished in {} msec, for {}",
                            state.partitionsProcessed,
                            FBUtilities.prettyPrintMemory(state.estimatedTotalBytes),
                            duration,
                            validator.desc);
            }
        }

        if(replicaRanges.size()>0){
            logger.debug("before createMerkleTreesForReplica, replicaRanges:{}", replicaRanges);
            // Create Merkle trees suitable to hold estimated partitions for the given ranges.
            // We blindly assume that a partition is evenly distributed on all sstables for now.
            MerkleTrees tree = createMerkleTreesForReplica(replicaRanges, cfs);
            long start = System.nanoTime();
            // validate the CF as we iterate over it
            validator.prepare(cfs, tree, topPartitionCollector);               
            //////////////////////////////////////
                // logger.debug("before getRangeRowAndInsertValidator, getValidated:{}", validator.getValidated());
                for (Range<Token> range : replicaRanges)
                {                                      
                    //ArrayList<Token> tokens = StorageService.instance.getTokenMetadata().sortedTokens();
                    List<InetAddress> ep = StorageService.instance.getNaturalEndpoints(cfs.keyspace.getName(), range.right);
                    if (!ep.get(0).equals(LOCAL)) {//the range is stored in replica copy
                        Map<String, byte[]> keyValueMap = new HashMap<String, byte[]>();
                        byte ip[] = ep.get(0).getAddress();  
                        int NodeID = (int)ip[3];
                        Token rightBound = StorageService.instance.getBoundToken(range.right);
                    }              
                }
                // logger.debug("after getRangeRowAndInsertValidator, getValidated:{}", validator.getValidated());
                /////////////////////////////////////
                validator.complete();
                long duration = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
                logger.debug("Validation finished in {} msec, for {}",
                             duration,
                             validator.desc);
        }

    }

    private static boolean isTopPartitionSupported(Validator validator)
    {
        // supported: --validate, --full, --full --preview
        switch (validator.getPreviewKind())
        {
            case NONE:
                return !validator.isIncremental;
            case ALL:
            case REPAIRED:
                return true;
            case UNREPAIRED:
                return false;
            default:
                throw new AssertionError("Unknown preview kind: " + validator.getPreviewKind());
        }
    }

    /**
     * Does not mutate data, so is not scheduled.
     */
    @Override
    public Future<?> submitValidation(ColumnFamilyStore cfs, Validator validator)
    {
        Callable<Object> validation = new Callable<Object>()
        {
            public Object call() throws IOException
            {
                try (TableMetrics.TableTimer.Context c = cfs.metric.validationTime.time())
                {
                    doValidation(cfs, validator);
                }
                catch (PreviewRepairConflictWithIncrementalRepairException | NoSuchRepairSessionException | CompactionInterruptedException e)
                {
                    validator.fail(e);
                    logger.warn(e.getMessage());
                }
                catch (Throwable e)
                {
                    // we need to inform the remote end of our failure, otherwise it will hang on repair forever
                    validator.fail(e);
                    logger.error("Validation failed.", e);
                    throw e;
                }
                return this;
            }
        };

        return cfs.getRepairManager().submitValidation(validation);
    }
}
