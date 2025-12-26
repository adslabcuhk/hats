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

package org.apache.cassandra.horse;


import java.net.InetAddress;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.ApplicationState;
import org.apache.cassandra.gms.EndpointState;
import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.horse.controller.RateLimiter;
import org.apache.cassandra.horse.leaderelection.election.ElectionBootstrap;
import org.apache.cassandra.horse.leaderelection.priorityelection.PriorityElectionBootstrap;
import org.apache.cassandra.horse.net.PolicyDistribute;
import org.apache.cassandra.horse.net.PolicyReplicate;
import org.apache.cassandra.horse.net.StatesGatheringSignal;
import org.apache.cassandra.horse.states.GlobalStates;
import org.apache.cassandra.horse.states.LocalStates;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.utils.FBUtilities;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;



/**
 * @author anonymous@gmail.com
 */

public class Scheduler {

    private static final Logger logger = LoggerFactory.getLogger(Scheduler.class);
    private static Boolean isPriorityElection = false;
    private static int priority = 100;
    private static Set<InetAddressAndPort> liveSeeds;

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

                PriorityElectionBootstrap.initElection(HorseUtils.getRaftLogPath(), 
                                        "ElectDataNodes", 
                                        DatabaseDescriptor.getListenAddress().getHostAddress() + ":"+DatabaseDescriptor.getRaftPort()+"::"+priority, 
                                        HorseUtils.InetAddressAndPortSetToString(Gossiper.instance.getLiveMembers(), 
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
                logger.info("HATSInfo: we now have the global states, latency vector is {}, request count vector is {}, score vector is {}, the load matrix is {}",
                             GlobalStates.globalStates.latencyVector, 
                             GlobalStates.globalStates.readCountOfEachNode, 
                             GlobalStates.globalStates.scoreVector, 
                             GlobalStates.globalStates.loadMatrix);
                    
                // Step2. Calculate the placement policy if needed.
                calculateGlobalPolicy();

                // Step3. Update local Policy
                LocalStates.updateLocalPolicy();

                // Step4. Acknowledge to the client driver
                StorageService.instance.notifyPolicy(GlobalStates.transformPolicyForClient());

                // Step5. Replicate the placement policy to the followers
                replicateGlobalPolicy();
                
                // Step6. Update the policy for background task control.
                RateLimiter.updateLimiter(GlobalStates.globalPolicy[Gossiper.getAllHosts().indexOf(FBUtilities.getBroadcastAddressAndPort())]);

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
            PolicyReplicate.sendPlacementPolicy(follower, GlobalStates.globalPolicy);
        }
    }

    // Note that we only send the partial placement policy to all the data nodes.
    private static void distributeCompactionRate()
    {
        if (liveSeeds.size() > 1)
        {
            for (InetAddressAndPort dataNode : Gossiper.instance.getLiveMembers())
            {
                if(liveSeeds.contains(dataNode))
                {
                    continue;
                }
                
                Double[] backgroundCompactionRate = new Double[GlobalStates.globalStates.rf];
                int nodeIndex = Gossiper.getAllHosts().indexOf(dataNode);
                for(int j = 0; j < GlobalStates.globalStates.rf; j++)
                {

                    // Calculate the rate limit for each replica
                    backgroundCompactionRate[j] = GlobalStates.globalPolicy[nodeIndex][j];
                }
                
                PolicyDistribute.sendPlacementPolicy(dataNode, backgroundCompactionRate);
            }
        }
    }

    /**
     * Calculate the placement policy.
     * 
     * Basic idea: To minimize the resource contention within a node, we initially place all the read 
     * requests of each replication group to the first $RCL$ replicas. Then we greedily adjust the placement 
     * policy of each replication group along the ring. For each node, we will compute a score based on the 
     * number of read requests and the mean value of the read latency within a period of time. Note that the
     * larger latency and the request count, the higher the score. We consider the following cases:
     * 
     * 1. If $node_i$ has a larger latency than $node_{i+1,...,i+M-1}$, we consider gently moving the load of 
     *    $RP_i$ to $node_{i+1,...,i+M-1}$. Here we just use a very simple algorithm to adjust the placement 
     *    policy, for example AIMD or fixed step size.
     * 2. If $node_i$ has a smaller latency than $node_{i+1,...,i+M-1}$, we consider recovering the load of 
     *    $RP_i$ from $node_{i+1,...,i+M-1}$.
     * 
     * Input: scoreVector, loadMatrix
     * Output: placementPolicy
     * 
     */
    private static void calculateGlobalPolicy()
    {
        logger.info("HATSInfo: Calculating placement policy, the old value is {}", Arrays.deepToString(GlobalStates.globalPolicy));

        for (int i = 0; i < GlobalStates.globalStates.nodeCount; i++)
        {

            double mean = 0.0;
            double stdDev = 0.0;

            for (int k = i; k < i + GlobalStates.globalStates.rf; k++)
            {
                mean += GlobalStates.globalStates.scoreVector[k % GlobalStates.globalStates.nodeCount];

            }
            mean = mean / GlobalStates.globalStates.rf;


            
            for (int k = i; k < i + GlobalStates.globalStates.rf; k++)
            {
                stdDev += Math.pow(GlobalStates.globalStates.scoreVector[k % GlobalStates.globalStates.nodeCount] - mean, 2);
            }
            stdDev = Math.sqrt(stdDev / GlobalStates.globalStates.rf);

            final double offloadThreshold = mean + stdDev;
            final double recoverThreshold = mean;

            if (GlobalStates.globalStates.scoreVector[i] >= offloadThreshold)
            {
                offloadRequests(i, recoverThreshold);
            }
            else if (GlobalStates.globalStates.scoreVector[i] < recoverThreshold)
            {
                recoverRequests(i, offloadThreshold);
            }
            else
            {
                logger.debug("HATSDebug: do nothing for node {}.", i);
            }
        }
        logger.info("HATSInfo: The new placement policy is {}", Arrays.deepToString(GlobalStates.globalPolicy));
    }

    /**
     * Offload the read requests for node[i], we consider which secondary replica node to be 
     * the target node and how many requests should be offloaded.
     * 
     */
    private static void offloadRequests(int primaryIndex, final double recoverThreshold)
    {
        // If the current node already has some requests to be offloaded, we do nothing
        if(GlobalStates.globalStates.deltaVector[primaryIndex] > 0)
        {
            return;
        }

        // Traverse every secondary replica node, and offload the request to the node with the lower score
        for(int i = primaryIndex + 1; i < primaryIndex + GlobalStates.globalStates.rf; i++)
        {
            int secondaryIndex = i % GlobalStates.globalStates.nodeCount;
            if(GlobalStates.globalStates.scoreVector[secondaryIndex] < recoverThreshold)
            {
                
                if(GlobalStates.globalPolicy[primaryIndex][0] <= 0)
                {
                    continue;
                }

                double stepSize = getStepSize(GlobalStates.globalStates.scoreVector[primaryIndex], GlobalStates.globalStates.scoreVector[secondaryIndex]);
                stepSize = stepSize > GlobalStates.globalPolicy[primaryIndex][0] ? GlobalStates.globalPolicy[primaryIndex][0] : stepSize;

                int replicaIndex = HorseUtils.getReplicaIndexForRGInEachNode(primaryIndex, i);

                GlobalStates.globalPolicy[primaryIndex][0] = 
                            HorseUtils.rounding(GlobalStates.globalPolicy[primaryIndex][0] - stepSize, 2);
                GlobalStates.globalPolicy[secondaryIndex][replicaIndex] = 
                            HorseUtils.rounding(GlobalStates.globalPolicy[secondaryIndex][replicaIndex] + stepSize, 2);
                GlobalStates.globalStates.deltaVector[replicaIndex] = 
                            HorseUtils.rounding(GlobalStates.globalStates.deltaVector[replicaIndex] - stepSize, 2);
                GlobalStates.globalStates.deltaVector[secondaryIndex] = 
                            HorseUtils.rounding(GlobalStates.globalStates.deltaVector[secondaryIndex] + stepSize, 2);
            }
        }
    }

    // Recover the request load
    private static void recoverRequests(int primaryIndex, final double offloadThreshold)
    {
        // Traverse every secondary replica node, and recover the request from the node with the higher score
        for(int i = primaryIndex + 1; i < primaryIndex + GlobalStates.globalStates.rf; i++)
        {
            int secondaryIndex = i % GlobalStates.globalStates.nodeCount;
            if(GlobalStates.globalStates.scoreVector[secondaryIndex] > GlobalStates.globalStates.scoreVector[primaryIndex])
            {
                int replicaIndex = HorseUtils.getReplicaIndexForRGInEachNode(primaryIndex, i);
                
                if(GlobalStates.globalPolicy[secondaryIndex][replicaIndex] <= 0)
                {
                    continue;
                }
                else
                {
                    double stepSize = getStepSize(GlobalStates.globalStates.scoreVector[primaryIndex], GlobalStates.globalStates.scoreVector[secondaryIndex]);
                    stepSize = stepSize > GlobalStates.globalPolicy[secondaryIndex][replicaIndex] ? GlobalStates.globalPolicy[secondaryIndex][replicaIndex] : stepSize;


                    GlobalStates.globalPolicy[primaryIndex][0] = 
                                HorseUtils.rounding(GlobalStates.globalPolicy[primaryIndex][0] + stepSize, 2);
                    GlobalStates.globalPolicy[secondaryIndex][replicaIndex] = 
                                HorseUtils.rounding(GlobalStates.globalPolicy[secondaryIndex][replicaIndex] - stepSize, 2);
                    GlobalStates.globalStates.deltaVector[primaryIndex] = 
                                HorseUtils.rounding(GlobalStates.globalStates.deltaVector[primaryIndex] + stepSize, 2);
                    GlobalStates.globalStates.deltaVector[secondaryIndex] = 
                                HorseUtils.rounding(GlobalStates.globalStates.deltaVector[secondaryIndex] - stepSize, 2);
                }
            }
        }
        
    }

    private static double getStepSize(double primaryScore, double secondaryScore)
    {
        return Math.min(0.1, HorseUtils.rounding(Math.abs(Math.pow((1 - secondaryScore / primaryScore), 3)), 2));
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

        GlobalStates.globalStates = new GlobalStates(Gossiper.getAllHosts().size(), 3);
        if(liveSeeds.size() == 1)
        {
            for (Map.Entry<InetAddressAndPort, EndpointState> entry : Gossiper.instance.endpointStateMap.entrySet())
            {
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
                    int replicaIndex = HorseUtils.getReplicaIndexFromGossipInfo(nodeIndex, entry1.getKey());
                    GlobalStates.globalStates.loadMatrix[nodeIndex][replicaIndex] = entry1.getValue();
                    GlobalStates.globalStates.readCountOfEachNode[nodeIndex] += entry1.getValue();
                }
                GlobalStates.globalStates.scoreVector[nodeIndex] = GlobalStates.getScore(GlobalStates.globalStates.latencyVector[nodeIndex], 
                                                                                         GlobalStates.globalStates.readCountOfEachNode[nodeIndex]);
            }
        }
        else if (liveSeeds.size() > 1)
        {
            logger.info("HATSInfo: Gathering the load statistic from the seed nodes {}", liveSeeds);
            StatesGatheringSignal signal = new StatesGatheringSignal(true);
            for(InetAddressAndPort seed : liveSeeds)
            {
                if(seed.equals(FBUtilities.getBroadcastAddressAndPort()))
                {
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
                    continue;
                }
                StorageService.instance.stateGatheringSignalInFlight.incrementAndGet();
                signal.sendStatesGatheringSignal(follower);
            }
        }
    }



    
    public static Runnable getPrintStatisticRunnable()
    {
        return new PrintStatisticRunnable();
    }

    private static class PrintStatisticRunnable implements Runnable
    {

        @Override
        public void run() {
            logger.info("HATSInfo: The Flush rate is {} mb/s,the coordinator read rate is {} mb/s, the compaction rate is {} mb/s, read request in flight is {}, the pending flush tasks are {}", 
                        StorageService.instance.flushRateMonitor.getRateInMB() * 4,
                        StorageService.instance.coordinatorReadRateMonitor.getRateInMB(),
                        StorageService.instance.compactionRateMonitor.getRateInMB(),
                        StorageService.instance.readRequestInFlight.get(),
                        StorageService.instance.pendingFlushRate.getRate());        
        }
        
    }

    public static void main(String[] args) {
        double value = 0.123456789;
        System.out.println(HorseUtils.rounding(value, 2));
    }

}
