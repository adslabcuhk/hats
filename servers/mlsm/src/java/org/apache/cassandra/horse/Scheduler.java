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


import java.math.BigDecimal;
import java.math.RoundingMode;
import java.net.InetAddress;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.ApplicationState;
import org.apache.cassandra.gms.EndpointState;
import org.apache.cassandra.gms.Gossiper;
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
                        Thread.sleep(10);
                        retryCount++;
                    } catch (InterruptedException e) {
                        e.printStackTrace();
                    }
                    if(retryCount > 10)
                    {
                        logger.warn("hatsWARN: we have waited for 100ms, but we still have {} states gathering signal in flight, so we stop this scheduling.", 
                                        StorageService.instance.stateGatheringSignalInFlight.get());
                        StorageService.instance.stateGatheringSignalInFlight.set(0);
                        return;
                    }
                }
                logger.info("HATSInfo: we now have the global states, the version vector is {}, latency vector is {}, request count vector is {}, score vector is {}, the load matrix is {}", 
                             GlobalStates.globalStates.versionVector, 
                             GlobalStates.globalStates.latencyVector, 
                             GlobalStates.globalStates.readCountOfEachNode, 
                             GlobalStates.globalStates.scoreVector, 
                             GlobalStates.globalStates.loadMatrix);
                    
                // Step2. Calculate the placement policy if needed.
                calculateGlobalPolicy();

                // Step3. Update local Policy
                LocalStates.updateLocalPolicy();

                // Step4. Replicate the placement policy to the followers
                replicateGlobalPolicy();
                
                // // Step5. Distribute the placement policy to the data nodes to control the background tasks
                // distributeCompactionRate();

                // // Step6. Acknowledge the client driver
                // acknowledgeClientDriver();
            }
        }
    }

    // We send the placement policy to all the live nodes
    private static void replicateGlobalPolicy()
    {

        // Get the followers
        // if(liveSeeds.size() > 1)
        // {
        //     for(InetAddressAndPort follower : liveSeeds)
        //     {
        //         if(follower.equals(FBUtilities.getBroadcastAddressAndPort()))
        //         {
        //             continue;
        //         }

        //         // Replicate the placement policy
        //         PolicyReplicate.sendPlacementPolicy(follower, GlobalStates.globalPolicy);
        //     }
        // }
        // else
        // {
        //     for(InetAddressAndPort follower : Gossiper.instance.getLiveMembers())
        //     {
        //         if (follower.equals(FBUtilities.getBroadcastAddressAndPort())) 
        //         {
        //             continue;
        //         }

        //         // Replicate the placement policy
        //         PolicyReplicate.sendPlacementPolicy(follower, GlobalStates.globalPolicy);
        //     }
        // }

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
                    backgroundCompactionRate[j] = GlobalStates.globalPolicy[nodeIndex][j][0];
                }
                
                PolicyDistribute.sendPlacementPolicy(dataNode, backgroundCompactionRate);
            }
        }
    }

    private static void acknowledgeClientDriver()
    {
        // [TODO] Acknowledge the client driver
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

            double min = Double.MAX_VALUE;
            double max = Double.MIN_VALUE;
            int minIndex = 0;
            int maxIndex = 0;
            for (int k = i; k < i + GlobalStates.globalStates.rf; k++)
            {
                if(min > GlobalStates.globalStates.scoreVector[k % GlobalStates.globalStates.nodeCount])
                {
                    min = GlobalStates.globalStates.scoreVector[k % GlobalStates.globalStates.nodeCount];
                    minIndex = k % GlobalStates.globalStates.nodeCount;
                }
                if(max < GlobalStates.globalStates.scoreVector[k % GlobalStates.globalStates.nodeCount])
                {
                    max = GlobalStates.globalStates.scoreVector[k % GlobalStates.globalStates.nodeCount];
                    maxIndex = k % GlobalStates.globalStates.nodeCount;
                }
            }

            int action = getAction(i, min, max);
            if(action == 1) // offload the request to the secondary replicas
            {
                offloadRequests(i, minIndex, maxIndex);
            }
            else if(action == 2) // recover the request from the secondary replicas
            {
                recoverRequests(i, minIndex, maxIndex);
            }
            else // do nothing
            {
                logger.debug("HATSDebug");
            }
        }
        logger.info("HATSInfo: The new placement policy is {}", Arrays.deepToString(GlobalStates.globalPolicy));
    }

    /**
     * Offload the read requests for node[i], we consider which secondary replica node to be 
     * the target node and how many requests should be offloaded.
     * 
     */
    private static void offloadRequests(int nodeIndex, int minIndex, int maxIndex)
    {
        if(maxIndex != nodeIndex)
            throw new IllegalArgumentException(String.format("The maxIndex %s should be %s", maxIndex, nodeIndex));

        // Traverse every secondary replica node, and offload the request to the node with the lower score
        for(int i = nodeIndex + 1; i < nodeIndex + GlobalStates.globalStates.rf; i++)
        {
            int targetIndex = i % GlobalStates.globalStates.nodeCount;
            double variance = getVariance(GlobalStates.globalStates.scoreVector[nodeIndex], 
                                          GlobalStates.globalStates.scoreVector[targetIndex]);
            if(variance >= GlobalStates.OFFLOAD_THRESHOLD)
            {
                if(GlobalStates.globalStates.deltaVector[targetIndex] >= GlobalStates.STEP_SIZE * (GlobalStates.globalStates.rf - 1))
                {
                    continue;
                }

                if(GlobalStates.globalPolicy[nodeIndex][0][0] < GlobalStates.STEP_SIZE)
                {
                    continue;
                }

                int replicaIndex = HorseUtils.getReplicaIndexForRGInEachNode(nodeIndex, i);

                GlobalStates.globalPolicy[nodeIndex][0][0] = 
                            rounding(GlobalStates.globalPolicy[nodeIndex][0][0] - GlobalStates.STEP_SIZE);
                GlobalStates.globalPolicy[targetIndex][replicaIndex][0] = 
                            rounding(GlobalStates.globalPolicy[targetIndex][replicaIndex][0] + GlobalStates.STEP_SIZE);
                GlobalStates.globalStates.deltaVector[replicaIndex] = 
                            rounding(GlobalStates.globalStates.deltaVector[replicaIndex] - GlobalStates.STEP_SIZE);
                GlobalStates.globalStates.deltaVector[targetIndex] = 
                            rounding(GlobalStates.globalStates.deltaVector[targetIndex] + GlobalStates.STEP_SIZE);
            }
        }
    }

    // Recover the request load
    private static void recoverRequests(int nodeIndex, int minIndex, int maxIndex)
    {
        if(minIndex != nodeIndex)
            throw new IllegalArgumentException(String.format("The minIndex %s should be %s", minIndex, nodeIndex));

        // Traverse every secondary replica node, and recover the request from the node with the higher score
        for(int i = nodeIndex + 1; i < nodeIndex + GlobalStates.globalStates.rf; i++)
        {
            int targetIndex = i % GlobalStates.globalStates.nodeCount;
            double variance = getVariance(GlobalStates.globalStates.scoreVector[targetIndex],
                                          GlobalStates.globalStates.scoreVector[nodeIndex]);
            if(variance >= GlobalStates.RECOVER_THRESHOLD)
            {
                int replicaIndex = HorseUtils.getReplicaIndexForRGInEachNode(nodeIndex, i);
                
                if(GlobalStates.globalPolicy[targetIndex][replicaIndex][0] < GlobalStates.STEP_SIZE)
                {
                    continue;
                }
                else
                {
                    double stepSize = GlobalStates.globalPolicy[targetIndex][replicaIndex][0] > GlobalStates.STEP_SIZE 
                                      ? GlobalStates.STEP_SIZE 
                                      : GlobalStates.globalPolicy[targetIndex][replicaIndex][0];

                    GlobalStates.globalPolicy[nodeIndex][0][0] = 
                                rounding(GlobalStates.globalPolicy[nodeIndex][0][0] + stepSize);
                    GlobalStates.globalPolicy[targetIndex][replicaIndex][0] = 
                                rounding(GlobalStates.globalPolicy[targetIndex][replicaIndex][0] - stepSize);
                    GlobalStates.globalStates.deltaVector[nodeIndex] = 
                                rounding(GlobalStates.globalStates.deltaVector[nodeIndex] + stepSize);
                    GlobalStates.globalStates.deltaVector[targetIndex] = 
                                rounding(GlobalStates.globalStates.deltaVector[targetIndex] - stepSize);
                }

            }
        }
        
    }

    private static double rounding(double value)
    {
        BigDecimal bd = new BigDecimal(Double.toString(value));
        bd = bd.setScale(3, RoundingMode.HALF_UP);
        return bd.doubleValue();
    }

    /**
     * 
     * @return 0 means do nothing for this RP, 
     *         1 means offload the request to the secondary replicas,
     *         2 means recover the request from the secondary replicas.
     */
    private static int getAction(int nodeIndex, double min, double max)
    {
        double variance = getVariance(max, min);

        if(min == GlobalStates.globalStates.scoreVector[nodeIndex] && variance >= GlobalStates.RECOVER_THRESHOLD)
        {
            return 2;
        }
        else if (max == GlobalStates.globalStates.scoreVector[nodeIndex] && variance >= GlobalStates.OFFLOAD_THRESHOLD)
        {
            return 1;
        }

        return 0;
    }

    private static double getVariance(double larger, double smaller)
    {
        return (larger - smaller) / smaller;
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
                    GlobalStates.globalStates.loadMatrix[nodeIndex][replicaIndex][0] = entry1.getValue();
                    GlobalStates.globalStates.readCountOfEachNode[nodeIndex] += entry1.getValue();
                }
                GlobalStates.globalStates.scoreVector[nodeIndex] = GlobalStates.getScore(GlobalStates.globalStates.latencyVector[nodeIndex], 
                                                                                         GlobalStates.globalStates.readCountOfEachNode[nodeIndex]);
            }
        }
        else if (liveSeeds.size() > 1)
        {
            StatesGatheringSignal signal = new StatesGatheringSignal(true);
            for(InetAddressAndPort seed : liveSeeds)
            {
                if(seed.equals(FBUtilities.getBroadcastAddressAndPort()))
                {
                    continue;
                }
                StorageService.instance.stateGatheringSignalInFlight.incrementAndGet();
                signal.sendStatesGatheringSignal(seed);
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

}
