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

package org.apache.cassandra.hats.states;


import java.io.Serializable;
import java.lang.reflect.Array;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.ApplicationState;
import org.apache.cassandra.gms.EndpointState;
import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.hats.HatsUtils;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.utils.FBUtilities;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import jnr.constants.platform.Local;


/**
 * @author anonymous@gmail.com
 */

public class GlobalStates implements Serializable {
    private static final Logger logger = LoggerFactory.getLogger(GlobalStates.class);

    public volatile static GlobalStates globalStates;    
    public static volatile Double[][] globalPolicy; // N X M
    public static final double OFFLOAD_THRESHOLD = DatabaseDescriptor.getOffloadThreshold();
    public static final double RECOVER_THRESHOLD = DatabaseDescriptor.getRecoverThreshold();
    public static final double STEP_SIZE = DatabaseDescriptor.getStepSize();
    public static LoadBalancingStrategy expectedStates = null;
    
    public static volatile int[] expectedRequestNumberofEachNode; // N
    public static volatile int[] expectedRequestNumberOfEachRG; // N
    // public static volatile int[][] expectedRequestDistribution; // N X M
    public Double[] scoreVector; // N
    public double[] latencyVector; // N
    public int[] readCountOfEachNode; // N
    // read count of each replication group
    public int[] readCountOfEachRG; // N
    public int[] updatingReadCountOfEachRG; // N
    public int[][] loadMatrix; // N X M
    public int[] versionVector; // N
    public Double[] deltaVector; // N
    public final int nodeCount;
    public static final int rf = DatabaseDescriptor.getReplicationFactor();

    public GlobalStates(int nodeCount)
    {
        this.nodeCount = nodeCount;
        initialization();
    }

    public static class LoadBalancingStrategy implements Serializable {
        public volatile int termId;
        public volatile int version;
        public volatile int[][] expectedRequestDistribution; // N X M

        public LoadBalancingStrategy(int termId, int version, int[][] expectedRequestDistribution)
        {
            this.termId = termId;
            this.version = version;
            this.expectedRequestDistribution = expectedRequestDistribution;
        }

    }

    public void initialization()
    {
        this.scoreVector = new Double[this.nodeCount];
        this.latencyVector = new double[this.nodeCount];
        this.readCountOfEachNode = new int[this.nodeCount];
        this.readCountOfEachRG = new int[this.nodeCount];
        this.updatingReadCountOfEachRG = new int[this.nodeCount];
        this.loadMatrix = new int[this.nodeCount][rf];
        this.versionVector = new int[this.nodeCount];
        this.deltaVector = new Double[this.nodeCount];
        for(int i = 0; i < this.nodeCount; i++)
        {
            this.scoreVector[i] = 0.0;
            this.latencyVector[i] = 0.0;
            this.readCountOfEachNode[i] = 0;
            this.readCountOfEachRG[i] = 0;
            this.updatingReadCountOfEachRG[i] = 0;
            this.versionVector[i] = 0;
            this.deltaVector[i] = 0.0;
            for(int j = 0; j < rf; j++)
            {
                this.loadMatrix[i][j] = 0;
            }
        }
    }

    public synchronized void mergeGlobalStates(final Map<InetAddress, LocalStates> gatheredStates, InetAddressAndPort from)
    {
        if(gatheredStates.size() != this.nodeCount)
        {
            logger.debug("HATSDebug: the gathered states number is not equal to the node count.");
        }

        // logger.info("HATSInfo: Received new states from {}, we start to merge it to the global states, the stateGatheringSignalInFlight is {}, gatheredStates is {}", from, StorageService.instance.stateGatheringSignalInFlight, gatheredStates);

        for (Map.Entry<InetAddress, LocalStates> entry : gatheredStates.entrySet())
        {
            int nodeIndex = Gossiper.getAllHosts().indexOf(InetAddressAndPort.getByAddress(entry.getKey()));
            if(nodeIndex == -1)
            {
                logger.error("hatsERROR: The node index is -1, the node is not in the host list.");
            }

            if(entry.getValue().version >= this.versionVector[nodeIndex])
            {
                this.versionVector[nodeIndex] = entry.getValue().version;
                this.latencyVector[nodeIndex] = entry.getValue().latency;
                this.readCountOfEachNode[nodeIndex] = 0;

                for (Map.Entry<InetAddress, Integer> entry1 : entry.getValue().completedReadRequestCount.entrySet())
                {
                    int replicaIndex = HatsUtils.getReplicaIndexFromGossipInfo(nodeIndex, entry1.getKey());
                    this.loadMatrix[nodeIndex][replicaIndex] = entry1.getValue();
                    this.readCountOfEachNode[nodeIndex] += entry1.getValue();
                }

                this.scoreVector[nodeIndex] = getScore(this.latencyVector[nodeIndex], this.readCountOfEachNode[nodeIndex]);

            }
            else
            {
                continue;
            }
        }
        StorageService.instance.stateGatheringSignalInFlight.decrementAndGet();
        // logger.info("HATSInfo: Received new states from {}, we merged it to the global states, the stateGatheringSignalInFlight is {}", from, StorageService.instance.stateGatheringSignalInFlight);
    }


    public static void updatePolicyForCurrentNode()
    {
        int nodeCount = Gossiper.getAllHosts().size();
        GlobalStates.expectedRequestNumberOfEachRG = new int[nodeCount];
        for (int i= 0; i < nodeCount; i++)
        {
            int requestCount = 0;
            for (int j = 0; j < rf; j++)
            {
                int curNodeIndex = (i + j) % nodeCount;
                requestCount += GlobalStates.expectedStates.expectedRequestDistribution[curNodeIndex][j];
            }
            GlobalStates.expectedRequestNumberOfEachRG[i] = requestCount;
        }
        
        GlobalStates.expectedRequestNumberofEachNode = new int[nodeCount];
        // Update expectedRequestNumberofEachNode
        for(int i = 0; i < nodeCount; i++)
        {
            int nodeIndex = i;
            int requestCount = 0;
            for(int j = 0; j < rf; j++)
            {
                requestCount += GlobalStates.expectedStates.expectedRequestDistribution[nodeIndex][j];
            }
            GlobalStates.expectedRequestNumberofEachNode[nodeIndex] = requestCount;

        }
        // Update globalPolicy
        LocalStates.transformToRatio();


        // update background policy for rate limiting
        translatePolicyForBackgroundController(FBUtilities.getBroadcastAddressAndPort());
    }


    public static void translatePolicyForBackgroundController(InetAddressAndPort targetNode)
    {

        int nodeIndex = Gossiper.getAllHosts().indexOf(targetNode);
        if(nodeIndex == -1)
        {
            throw new IllegalStateException("The node index is -1, the node is not in the host list.");
        }
        Double[] localPolicyForBackgroundController = new Double[rf];
        for(int i = 0; i < rf; i++)
        {
            localPolicyForBackgroundController[i] = (double) GlobalStates.expectedStates.expectedRequestDistribution[nodeIndex][i] / GlobalStates.expectedRequestNumberofEachNode[nodeIndex];
        }
        logger.info("HATSInfo: the request count of the node is {}, the expected request distribution current node is {}, policy for background controller {}", 
                    GlobalStates.expectedRequestNumberofEachNode[nodeIndex], Arrays.toString(GlobalStates.expectedStates.expectedRequestDistribution[nodeIndex]), Arrays.toString(localPolicyForBackgroundController));
        LocalStates.backgroundPolicy = localPolicyForBackgroundController;
    }

    public static double getScore(double latency, int requestCount)
    {
        double score = latency;

        return score;
    }

    public static void initializeGlobalPolicy()
    {
        int nodeCount = StringUtils.split(DatabaseDescriptor.getAllHosts(), ',').length;
        globalPolicy = new Double[nodeCount][rf];
        expectedRequestNumberofEachNode = new int[nodeCount];
        expectedRequestNumberOfEachRG = new int[nodeCount];
        for(int i = 0; i < nodeCount; i++)
        {
            expectedRequestNumberofEachNode[i] = 0;
            expectedRequestNumberOfEachRG[i] = 0;
            globalPolicy[i][0] = 1.0;
            for(int j = 1; j < rf; j++)
            {
                globalPolicy[i][j] = 0.0;
            }
        }
        logger.debug("HATSDebug: Initialize the placement policy as {}, the host count is {}, host count in configuration file {}",  
                     Arrays.deepToString(globalPolicy), 
                     Gossiper.getAllHosts().size(), 
                     StringUtils.split(DatabaseDescriptor.getAllHosts(), ','));
    }

    public static Map<String, List<Double>> transformPolicyForClient()
    {
        final Double[][] policy = globalPolicy;
        Map<String, List<Double>> policyForClient = new HashMap<String, List<Double>>();

        if(policy.length != Gossiper.getAllHosts().size())
        {
            throw new IllegalStateException("The policy length is not equal to the host count");
        }

        List<Long> tokenList = new ArrayList<Long>(Gossiper.getTokenRanges());
        // logger.info("HATSInfo: The token list before sorting is {}", tokenList);
        Collections.sort(tokenList);
        // logger.info("HATSInfo: The token list after sorting is {}", tokenList);
        int nodeCount = tokenList.size();

        for(int i = 0; i < policy.length; i++)
        {
            List<Double> rgPolicy = new ArrayList<Double>();
            for(int curNodeIndex = i; curNodeIndex < i + rf; curNodeIndex++)
            {
                int replicaIndex = HatsUtils.getReplicaIndexForRGInEachNode(i, curNodeIndex);
                rgPolicy.add(policy[curNodeIndex % nodeCount][replicaIndex]);
            }
            policyForClient.put(tokenList.get(i).toString(), rgPolicy);
        }
        logger.info("HATSInfo: The policy for client is {}, policy is {}", policyForClient, policy);
        return policyForClient;
    }

    public static class StatesForClients implements Serializable
    {
        public final Map<String, List<Double>> policy;
        public final Map<InetAddress, Double> coordinatorReadLatency;
        
        public StatesForClients(Map<String, List<Double>> policy, Map<InetAddress, Double> coordinatorReadLatency)
        {
            this.policy = policy;
            this.coordinatorReadLatency = coordinatorReadLatency;
        }
    }

    public Map<InetAddress, Double> getGlobalCoordinatorReadLatency()
    {
        Map<InetAddress, Double> coordinatorReadLatency = new HashMap<>();

        if(this.latencyVector.length != Gossiper.getAllHosts().size())
            throw new IllegalStateException(String.format("HATSERROR: the latency vector length %s is not equal to the host vector length %s", this.latencyVector.length, Gossiper.getAllHosts().size()));

        for(int i = 0; i < this.latencyVector.length; i++)
        {
            coordinatorReadLatency.put(Gossiper.getAllHosts().get(i).getAddress(), this.latencyVector[i]);
        }

        return coordinatorReadLatency;
    }

    public static Map<InetAddress, Double> getGlobalCoordinatorReadLatencyFromGossipInfo()
    {
        Map<InetAddress, Double> coordinatorReadLatency = new HashMap<>();

        for(Map.Entry<InetAddressAndPort, EndpointState> entry : Gossiper.instance.endpointStateMap.entrySet())
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

            coordinatorReadLatency.put(entry.getKey().getAddress(), localStates.latency);

        }

        return coordinatorReadLatency;
    }
}
