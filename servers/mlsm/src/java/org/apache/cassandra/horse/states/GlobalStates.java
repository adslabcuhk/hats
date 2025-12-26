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

package org.apache.cassandra.horse.states;


import java.io.Serializable;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.horse.HorseUtils;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.service.StorageService;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class GlobalStates implements Serializable {
    private static final Logger logger = LoggerFactory.getLogger(GlobalStates.class);

    public static GlobalStates globalStates;    
    public static volatile Double[][][] globalPolicy; // N X M X 1
    public static final double OFFLOAD_THRESHOLD = DatabaseDescriptor.getOffloadThreshold();
    public static final double RECOVER_THRESHOLD = DatabaseDescriptor.getRecoverThreshold();
    public static final double STEP_SIZE = DatabaseDescriptor.getStepSize();
    
    public Double[] scoreVector; // N
    public Double[] latencyVector; // N
    public int[] readCountOfEachNode; // N
    public int[][][] loadMatrix; // N X M X 1
    public int[] versionVector; // N
    public Double[] deltaVector; // N
    public final int nodeCount;
    public final int rf;

    public GlobalStates(int nodeCount, int rf)
    {
        this.nodeCount = nodeCount;
        this.rf = rf;
        initialization();
    }

    public void initialization()
    {
        this.scoreVector = new Double[this.nodeCount];
        this.latencyVector = new Double[this.nodeCount];
        this.readCountOfEachNode = new int[this.nodeCount];
        this.loadMatrix = new int[this.nodeCount][this.rf][1];
        this.versionVector = new int[this.nodeCount];
        this.deltaVector = new Double[this.nodeCount];
        for(int i = 0; i < this.nodeCount; i++)
        {
            this.scoreVector[i] = 0.0;
            this.latencyVector[i] = 0.0;
            this.readCountOfEachNode[i] = 0;
            this.versionVector[i] = 0;
            this.deltaVector[i] = 0.0;
            for(int j = 0; j < this.rf; j++)
            {
                this.loadMatrix[i][j][0] = 0;
            }
        }
    }

    public synchronized void mergeGlobalStates(Map<InetAddress, LocalStates> gatheredStates)
    {
        if(gatheredStates.size() != this.nodeCount)
        {
            logger.debug("HATSDebug: the gathered states number is not equal to the node count.");
        }

        for (Map.Entry<InetAddress, LocalStates> entry : gatheredStates.entrySet())
        {
            int nodeIndex = Gossiper.getAllHosts().indexOf(InetAddressAndPort.getByAddress(entry.getKey()));
            if(nodeIndex == -1)
            {
                throw new IllegalStateException("Host not found in Gossiper");
            }

            if(entry.getValue().version >= globalStates.versionVector[nodeIndex])
            {
                globalStates.versionVector[nodeIndex] = entry.getValue().version;
                globalStates.latencyVector[nodeIndex] = entry.getValue().latency;
                globalStates.readCountOfEachNode[nodeIndex] = 0;

                for (Map.Entry<InetAddress, Integer> entry1 : entry.getValue().completedReadRequestCount.entrySet())
                {
                    int replicaIndex = HorseUtils.getReplicaIndexFromGossipInfo(nodeIndex, entry1.getKey());
                    globalStates.loadMatrix[nodeIndex][replicaIndex][0] = entry1.getValue();
                    globalStates.readCountOfEachNode[nodeIndex] += entry1.getValue();
                }

                globalStates.scoreVector[nodeIndex] = getScore(globalStates.latencyVector[nodeIndex], globalStates.readCountOfEachNode[nodeIndex]);

            }
            else
            {
                continue;
            }
        }

        StorageService.instance.stateGatheringSignalInFlight.decrementAndGet();
    }

    public static double getScore(double latency, int requestCount)
    {
        double score = latency;

        return score;
    }

    public static void initializeGlobalPolicy()
    {
        int nodeCount = StringUtils.split(DatabaseDescriptor.getAllHosts(), ',').length;
        globalPolicy = new Double[nodeCount][3][1];
        for(int i = 0; i < nodeCount; i++)
        {
            globalPolicy[i][0][0] = 1.0;
            for(int j = 1; j < 3; j++)
            {
                globalPolicy[i][j][0] = 0.0;
            }
        }
        logger.debug("HATSDebug: Initialize the placement policy as {}, the host count is {}, host count in configuration file {}",  
                     Arrays.deepToString(globalPolicy), 
                     Gossiper.getAllHosts().size(), 
                     StringUtils.split(DatabaseDescriptor.getAllHosts(), ','));
    }

    public static Map<String, List<Double>> transformPolicyForClient()
    {
        final Double[][][] policy = globalPolicy;
        Map<String, List<Double>> policyForClient = new HashMap<String, List<Double>>();

        if(policy.length != Gossiper.getAllHosts().size())
        {
            throw new IllegalStateException("The policy length is not equal to the host count");
        }

        List<Long> tokenList = new ArrayList<Long>(Gossiper.getTokenRanges());
        int nodeCount = tokenList.size();

        for(int i = 0; i < policy.length; i++)
        {
            List<Double> rgPolicy = new ArrayList<Double>();
            for(int curNodeIndex = i; curNodeIndex < i + 3; curNodeIndex++)
            {
                int replicaIndex = HorseUtils.getReplicaIndexForRGInEachNode(i, curNodeIndex);
                rgPolicy.add(policy[curNodeIndex % nodeCount][replicaIndex][0]);
            }
            policyForClient.put(tokenList.get(i).toString(), rgPolicy);
        }

        return policyForClient;
    }

}
