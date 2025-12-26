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

package org.apache.cassandra.hats;


import java.net.InetAddress;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.ApplicationState;
import org.apache.cassandra.gms.EndpointState;
import org.apache.cassandra.gms.GossipDigestSyn;
import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.hats.controller.BackgroundController;
import org.apache.cassandra.hats.controller.LoadBalancer;
import org.apache.cassandra.hats.leaderelection.election.ElectionBootstrap;
import org.apache.cassandra.hats.leaderelection.priorityelection.PriorityElectionBootstrap;
import org.apache.cassandra.hats.net.GossipStatesDigest;
import org.apache.cassandra.hats.net.PolicyReplicate;
import org.apache.cassandra.hats.net.RequestNewStates;
import org.apache.cassandra.hats.net.StatesGatheringSignal;
import org.apache.cassandra.hats.states.GlobalStates;
import org.apache.cassandra.hats.states.LocalStates;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.net.Message;
import org.apache.cassandra.net.MessagingService;
import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.utils.FBUtilities;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.common.collect.ImmutableList;



/**
 * @author anonymous@gmail.com
 */

public class Scheduler {

    private static final Logger logger = LoggerFactory.getLogger(Scheduler.class);
    private static Boolean isPriorityElection = false;
    private static int priority = 100;
    private static Set<InetAddressAndPort> liveSeeds;
    public static AtomicInteger version = new AtomicInteger(0);

    private static final Random random = new Random();

    private static final String ANSI_RESET = "\u001B[0m";
    private static final String ANSI_RED = "\u001B[31m";
    private static final String ANSI_YELLOW = "\u001B[33m";
    private static final String ANSI_BLUE = "\u001B[34m";

    public static Runnable getLeaderElectionRunnable()
    {
        return new LeaderElectionRunnable();
    }

    private static class LeaderElectionRunnable implements Runnable
    {
        // Check the seed node status, if there is less than one seed node, change the election scheme
        @Override
        public void run() {
            liveSeeds = Gossiper.getAllSeeds().stream().filter(Gossiper.instance::isAlive).collect(Collectors.toSet());
            
            // Step1. Start a new leader election scheme if needed
            if (!getIsPriorityElection() && liveSeeds.size() <= 1)
            {
                logger.debug("HATSDebug: no more than 1 seed node is alive, we need to change the election scheme. Lived seed node is {}, live members are: {}", liveSeeds, Gossiper.instance.getLiveMembers());

                setIsPriorityElection(true);
                ElectionBootstrap.shutdownElection(liveSeeds);
                if(liveSeeds.contains(FBUtilities.getBroadcastAddressAndPort()))
                {
                    priority = 1000000000;
                }

                PriorityElectionBootstrap.initElection(HatsUtils.getRaftLogPath(), 
                                        "ElectDataNodes", 
                                        DatabaseDescriptor.getListenAddress().getHostAddress() + ":"+DatabaseDescriptor.getRaftPort()+"::"+priority, 
                                        HatsUtils.InetAddressAndPortSetToString(Gossiper.instance.getLiveMembers(), 
                                                                                 DatabaseDescriptor.getRaftPort(), 
                                                                                 liveSeeds));
            }
            // else
            // {
            //     logger.debug("HATSDebug: isPriorityElection: {}, seenAnySeed: {}, liveMembers: {}, seed nodes are: {}", getIsPriorityElection(), Gossiper.instance.seenAnySeed(), Gossiper.instance.getLiveMembers(), Gossiper.instance.getSeeds());
            // }

        }
        
    }

    public static Boolean getIsPriorityElection()
    {
        return isPriorityElection;
    }

    public static void setIsPriorityElection(Boolean isPriorityElection)
    {
        Scheduler.isPriorityElection = isPriorityElection;
    }


    public static Runnable getSchedulerRunnable()
    {
        return new SchedulerRunnable();
    }

    private static class SchedulerRunnable implements Runnable
    {
        @Override
        public void run()
        {

            if(ElectionBootstrap.isStarted() || PriorityElectionBootstrap.isStarted())
            {
                if(GlobalStates.globalPolicy == null)
                {
                    GlobalStates.initializeGlobalPolicy();                
                }
            }
            else
            {
                return;
            }

            if (ElectionBootstrap.isLeader() || PriorityElectionBootstrap.isLeader())
            {
                logger.debug("HATSDebug: Node {} is the leader. Start the scheduler.", FBUtilities.getBroadcastAddressAndPort());

                // Step1. Gather the load statistic
                gatheringLoadStatistic();
                    
                // Step2. Calculate the placement policy if needed.
                calculateGlobalPolicy();

                // Step3. Update local Policy for coordinator
                GlobalStates.updatePolicyForCurrentNode();

                // Step4. Acknowledge to the client driver
                StorageService.instance.notifyPolicy(GlobalStates.transformPolicyForClient(), GlobalStates.globalStates.getGlobalCoordinatorReadLatency());

                // Step5. Replicate the placement policy to the followers
                // Todo: replace gossip with this naive approach
                // replicateGlobalPolicy();
            }
        }
    }

    // We send the placement policy to all the live nodes
    private static void replicateGlobalPolicy()
    {
        for(InetAddressAndPort follower : Gossiper.instance.getLiveMembers())
        {
            if (follower.equals(FBUtilities.getBroadcastAddressAndPort())) 
            {
                continue;
            }

            // Replicate the placement policy
            PolicyReplicate.sendPlacementPolicy(follower, GlobalStates.expectedStates);
        }
    }

    /**
     * Calculate the placement policy.
     */
    private static void calculateGlobalPolicy()
    {
        // logger.info(ANSI_YELLOW+"HATSInfo: Calculating placement policy, the old value is {}"+ ANSI_RESET, Arrays.deepToString(GlobalStates.globalPolicy));
        // print the transposed load matrix
        logger.info("HATSInfo: The load matrix is:");
        for (int i = 0; i < GlobalStates.rf; i++)
        {
            StringBuilder row = new StringBuilder();  // To accumulate the row data
            for (int j = 0; j < GlobalStates.globalStates.nodeCount; j++)
            {
                row.append(String.format("%10d ", GlobalStates.globalStates.loadMatrix[j][i]));
            }
            logger.info(row.toString());  // Log the entire row at once
        }
        
        logger.info("HATSInfo: the average latency of each node:");
        logger.info("{}", Arrays.toString(GlobalStates.globalStates.latencyVector));

        GlobalStates.globalPolicy = LoadBalancer.balanceLoad(GlobalStates.globalStates.nodeCount, 
                                                             GlobalStates.rf, 
                                                             DatabaseDescriptor.getSchedulingInterval(), 
                                                             GlobalStates.globalStates.latencyVector, 
                                                             GlobalStates.globalStates.loadMatrix);


        // logger.info(ANSI_YELLOW+"HATSInfo: The new placement policy is {}"+ ANSI_RESET, Arrays.deepToString(GlobalStates.globalPolicy));
    }


    /**
    * Gather the load statistic has three cases:
    * 1. If we have multiple live seed nodes, we gathering the load statistic from these seed nodes
    * 2. If we have only one live seed node, we gathering the load statistic locally
    * 3. If we have no live seed node, we gathering the load statistic from all live members
    */
    public static void gatheringLoadStatistic()
    {
        // Check if this node is the leader
        if (!ElectionBootstrap.isLeader() && !PriorityElectionBootstrap.isLeader())
        {
            throw new IllegalStateException("This method should be called by the leader node.");
        }
        // logger.debug("HATSDebug: Node {} is the leader. Start the scheduler.", FBUtilities.getBroadcastAddressAndPort());

        
        StorageService.instance.stateGatheringSignalInFlight.set(0);

        GlobalStates.globalStates = new GlobalStates(Gossiper.getAllHosts().size());
        if(liveSeeds.size() == 1)
        {
            makeSnapshotForGossipInfo();
        }
        else if (liveSeeds.size() > 1)
        {
            logger.info("HATSInfo: Gathering the load statistic from the seed nodes {}", liveSeeds);
            StatesGatheringSignal signal = new StatesGatheringSignal(true);
            for(InetAddressAndPort seed : liveSeeds)
            {
                if(seed.equals(FBUtilities.getBroadcastAddressAndPort()))
                {
                    makeSnapshotForGossipInfo();
                    continue;
                }
                StorageService.instance.stateGatheringSignalInFlight.incrementAndGet();
                signal.sendStatesGatheringSignal(seed);
                logger.info("HATSInfo: send the signal to the seed node {}, the stateGatheringSignalInFlight is {}", seed, StorageService.instance.stateGatheringSignalInFlight.get());
            }
        }
        else
        {
            StatesGatheringSignal signal = new StatesGatheringSignal(false);
            for(InetAddressAndPort follower : Gossiper.instance.getLiveMembers())
            {
                if(follower.equals(FBUtilities.getBroadcastAddressAndPort()))
                {
                    makeSnapshotForGossipInfo();
                    continue;
                }
                StorageService.instance.stateGatheringSignalInFlight.incrementAndGet();
                signal.sendStatesGatheringSignal(follower);
            }
        }

        // Wait until we get all the states

        int retryCount = 0;
        while(StorageService.instance.stateGatheringSignalInFlight.get() != 0)
        {
            try {
                Thread.sleep(1000);
                retryCount++;
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
            if(retryCount >= 5)
            {
                logger.warn("hatsWARN: we have waited for 5s, but we still have {} states gathering signal in flight, so we stop this scheduling.", 
                                StorageService.instance.stateGatheringSignalInFlight.get());
                StorageService.instance.stateGatheringSignalInFlight.set(0);
                return;
            }
        }

        // update the readCountOfEachRg
        for(int i = 0; i < GlobalStates.globalStates.nodeCount; i++)
        {
            for(int j = 0; j < GlobalStates.rf; j++)
            {
                // int rgIndex = HatsUtils.getReplicaIndexForRGInEachNode(i, i + j);
                int rgIndex = (i - j + GlobalStates.globalStates.nodeCount) % GlobalStates.globalStates.nodeCount;
                GlobalStates.globalStates.updatingReadCountOfEachRG[rgIndex] += GlobalStates.globalStates.loadMatrix[i][j];
            }
        }
        
        GlobalStates.globalStates.readCountOfEachNode = Arrays.copyOf(GlobalStates.globalStates.updatingReadCountOfEachRG, GlobalStates.globalStates.nodeCount);
        GlobalStates.globalStates.updatingReadCountOfEachRG = new int[GlobalStates.globalStates.nodeCount];

        logger.info(ANSI_RED + "HATSInfo: we now have the global states, request count vector is {}, score vector is {}, the load matrix is {}"+ ANSI_RESET,
                    //  GlobalStates.globalStates.latencyVector, 
                     GlobalStates.globalStates.readCountOfEachNode, 
                     GlobalStates.globalStates.scoreVector, 
                     GlobalStates.globalStates.loadMatrix);

    }


    private static void makeSnapshotForGossipInfo()
    {
        for (Map.Entry<InetAddressAndPort, EndpointState> entry : Gossiper.instance.endpointStateMap.entrySet())
        {
            logger.info("HATSInfo: the endpoint {} state is {}, foreground load is {}", entry.getKey(), entry.getValue(),  entry.getValue().getApplicationState(ApplicationState.FOREGROUND_LOAD));
            String localStatesStr = entry.getValue().getApplicationState(ApplicationState.FOREGROUND_LOAD).value;
            int version = entry.getValue().getApplicationState(ApplicationState.FOREGROUND_LOAD).version;

            LocalStates localStates = LocalStates.fromString(localStatesStr, version);

            if(localStates == null)
            {
                continue;
            }

            int nodeIndex = Gossiper.getAllHosts().indexOf(entry.getKey());
            if (nodeIndex == -1)
            {
                throw new IllegalStateException("Host not found in Gossiper");
            }

            GlobalStates.globalStates.latencyVector[nodeIndex] = localStates.latency;
            GlobalStates.globalStates.versionVector[nodeIndex] = localStates.version;
            GlobalStates.globalStates.readCountOfEachNode[nodeIndex] = 0;
            for (Map.Entry<InetAddress, Integer> entry1 : localStates.completedReadRequestCount.entrySet())
            {
                int replicaIndex = HatsUtils.getReplicaIndexFromGossipInfo(nodeIndex, entry1.getKey());
                GlobalStates.globalStates.loadMatrix[nodeIndex][replicaIndex] = entry1.getValue();
                GlobalStates.globalStates.readCountOfEachNode[nodeIndex] += entry1.getValue();
            }
            GlobalStates.globalStates.scoreVector[nodeIndex] = GlobalStates.getScore(GlobalStates.globalStates.latencyVector[nodeIndex], 
                                                                                     GlobalStates.globalStates.readCountOfEachNode[nodeIndex]);
        }
    }


    public static Runnable startGossipStatesRunnable()
    {
        return new GossipStatesRunnable();
    }

    private static class GossipStatesRunnable implements Runnable
    {
        @Override
        public void run()
        {
            InetAddressAndPort to = selectNodesForGossip(Gossiper.instance.getLiveMembers());
            if(GlobalStates.expectedStates == null)
            {
                // request new states from a random node
                RequestNewStates.requestNewExpectedStates(to);
                InetAddressAndPort maybeToSeed = maybeGossipToSeed();
                if (maybeToSeed != null) 
                {
                    RequestNewStates.requestNewExpectedStates(maybeToSeed);
                }
            }
            else
            {
                logger.info("HATSInfo: Gossip the new states to the node {}", to);
                // gossip new states to a random node
                GossipStatesDigest.sendStatesDisgestMessage(to, GlobalStates.expectedStates.termId, GlobalStates.expectedStates.version);
                InetAddressAndPort maybeToSeed = maybeGossipToSeed();
                if (maybeToSeed != null) 
                {
                    GossipStatesDigest.sendStatesDisgestMessage(maybeToSeed, GlobalStates.expectedStates.termId, GlobalStates.expectedStates.version);
                }
            }
            
        }
    }


    private static InetAddressAndPort selectNodesForGossip(Iterable<InetAddressAndPort> epSet)
    {
        List<InetAddressAndPort> endpoints = ImmutableList.copyOf(epSet);

        int size = endpoints.size();
        /* Generate a random number from 0 -> size */
        int index = (size == 1) ? 0 : random.nextInt(size);
        InetAddressAndPort to = endpoints.get(index);
        return to;
    }

    private static InetAddressAndPort maybeGossipToSeed()
    {
        int size = Gossiper.getAllSeeds().size();
        if (size > 0)
        {
            if (size == 1 && Gossiper.getAllSeeds().contains(StorageService.instance.localAddressAndPort))
            {
                return null;
            }

            if (Gossiper.instance.getLiveMembers().size() == 0)
            {
                return selectNodesForGossip(Gossiper.getAllSeeds());
            }
            else
            {
                /* Gossip with the seed with some probability. */
                double probability = Gossiper.getAllSeeds().size() / (double) (Gossiper.instance.getLiveMembers().size() + Gossiper.instance.getUnreachableMembers().size());
                double randDbl = random.nextDouble();
                if (randDbl <= probability)
                    return selectNodesForGossip(Gossiper.getAllSeeds());
            }
        }
        return null;
    }



    
    public static Runnable getPrintStatisticRunnable()
    {
        return new PrintStatisticRunnable();
    }

    private static class PrintStatisticRunnable implements Runnable
    {

        @Override
        public void run() {
            logger.info("HATSInfo: The Flush rate is {} mb/s, the compaction rate is {} mb/s, read request in flight is {}, the get endpoint cost is {} us, foreground load {}, local read latency: {}, local read count: {}, local write latency: {}, local write count: {}", 
                        StorageService.instance.flushRateMonitor.getRateInMB() * 3,
                        // StorageService.instance.coordinatorReadRateMonitor.getRateInMB(),
                        // StorageService.instance.localReadRateMonitor.getRateInMB(),
                        StorageService.instance.compactionRateMonitor.getRateInMB(),
                        StorageService.instance.readRequestInFlight.get(),
                        // StorageService.instance.pendingFlushRate.getRate(),
                        StorageService.instance.getEndpointCost.get() / 1000,
                        StorageService.instance.totalReadCntOfEachReplica, 
                        StorageService.instance.localReadLatencyCalculator.getLatencyForLocalStates(),
                        StorageService.instance.localReadLatencyCalculator.getCount(), 
                        StorageService.instance.writeLatencyCalculator.getLatencyForLocalStates(), 
                        StorageService.instance.writeLatencyCalculator.getCount());        
        }
        
    }

    public static void main(String[] args) {
        double value = 0.123456789;
        System.out.println(HatsUtils.rounding(value, 2));
    }

}
