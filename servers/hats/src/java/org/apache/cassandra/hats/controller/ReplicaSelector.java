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

package org.apache.cassandra.hats.controller;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.hats.states.GlobalStates;
import org.apache.cassandra.hats.states.LocalStates;
import org.apache.cassandra.locator.DynamicEndpointSnitch;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.service.StorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


/**
 * @author anonymous@gmail.com
*/

public class ReplicaSelector 
{

    private static final Logger logger = LoggerFactory.getLogger(ReplicaSelector.class);
    public final static RandomSelector randomSelector = new RandomSelector();
    /**
     * 1. It can periodically update the score based on the placement policy and the sampling latency
    */
    private static Random random = new Random();

    public static volatile SnitchMetrics snitchMetrics= new SnitchMetrics(new ConcurrentHashMap<InetAddressAndPort, Double>(), 1, 1);

    public static class SnitchMetrics 
    {
        public final ConcurrentHashMap<InetAddressAndPort, Double> sampleLatency;
        public final double minLatency;
        public final double maxLatency;
        public final ConcurrentHashMap<InetAddressAndPort, ConcurrentHashMap<InetAddressAndPort, Double>> cachedScores;

        public SnitchMetrics(ConcurrentHashMap<InetAddressAndPort, Double> sampleLatency, double minLatency, double maxLatency) 
        {
            this.sampleLatency = sampleLatency;
            this.minLatency = minLatency;
            this.maxLatency = maxLatency;
            this.cachedScores = new ConcurrentHashMap<InetAddressAndPort, ConcurrentHashMap<InetAddressAndPort, Double>>();
        }
        
    }


    public static double getScore(InetAddressAndPort replicationGroup, InetAddressAndPort targetAddr, boolean isRangeRequest) {
        int targetIndex = Gossiper.getAllHosts().indexOf(targetAddr);

        if(GlobalStates.expectedRequestNumberofEachNode == null || GlobalStates.expectedRequestNumberofEachNode[targetIndex] == 0)
        {
            Map<InetAddressAndPort, Double> groupScores = snitchMetrics.cachedScores.computeIfAbsent(replicationGroup, k -> new ConcurrentHashMap<>());

            // Return score if already calculated
            Double score = groupScores.get(targetAddr);
            if (score != null) {
                return score;
            }
        
            // Calculate score because it was not found in cache
            double newScore = calculateScore(replicationGroup, targetAddr, isRangeRequest, targetIndex);
            groupScores.put(targetAddr, newScore);
            return newScore;
        }
        else
        {
            return calculateScore(replicationGroup, targetAddr, isRangeRequest, targetIndex);
        }
    }
    
    private static double calculateScore(InetAddressAndPort replicationGroup, InetAddressAndPort targetAddr, boolean isRangeRequest, int targetIndex) {
        double greedyScore = calculateGreedyScore(replicationGroup, targetAddr);
        double latencyScore = calculateLatencyScore(replicationGroup, targetAddr, targetIndex);
        if (isRangeRequest) 
            return latencyScore;
        if(GlobalStates.expectedRequestNumberofEachNode == null || GlobalStates.expectedRequestNumberofEachNode[targetIndex] == 0 || latencyScore <= 1)
        {
            return greedyScore + latencyScore;
        }
        // logger.info("HATSInfo: the expected request number is {}, the latency score is {}, the score is {}", GlobalStates.expectedRequestNumberofEachNode[targetIndex], latencyScore, latencyScore - GlobalStates.expectedRequestNumberofEachNode[targetIndex]);
        return latencyScore - GlobalStates.expectedRequestNumberofEachNode[targetIndex];
    }
    
    private static double calculateGreedyScore(InetAddressAndPort replicationGroup, InetAddressAndPort targetAddr) 
    {
        double greedyScore = 0.0;
        if(LocalStates.localPolicyWithAddress.get(replicationGroup) != null)
        {
            greedyScore = LocalStates.localPolicyWithAddress.get(replicationGroup).get(targetAddr);
        }
        return greedyScore;
    }
    
    private static double calculateLatencyScore(InetAddressAndPort replicationGroup,InetAddressAndPort targetAddr, int targetIndex) {
        double latencyScore = 0.0;
        // Use the old score function
        if(GlobalStates.expectedRequestNumberofEachNode == null || GlobalStates.expectedRequestNumberofEachNode[targetIndex] == 0)
        {
            if(targetAddr.equals(StorageService.instance.localAddressAndPort))
            {
                latencyScore = 1.0;
            }
            else if(snitchMetrics.sampleLatency.containsKey(targetAddr))
            {
                latencyScore = snitchMetrics.minLatency / snitchMetrics.sampleLatency.get(targetAddr);
            }
            else
            {
                logger.info("HATSInfo: sample latency does not contain: {}", targetAddr);
                latencyScore = 1.0 + (snitchMetrics.maxLatency/1000 - 1.0) * random.nextDouble();
            }
        }
        else
        {
            // use the new score function
            if(DynamicEndpointSnitch.ewmaSamples.containsKey(replicationGroup) && DynamicEndpointSnitch.ewmaSamples.get(replicationGroup).containsKey(targetAddr))
            {
                // micro to seconds
                double replicaLatency = (DynamicEndpointSnitch.ewmaSamples.get(replicationGroup).get(targetAddr)) / 1000000;
                latencyScore = (4 * DatabaseDescriptor.getSchedulingInterval()) / replicaLatency;
            }
            else
            {
                logger.info("HATSInfo: sample latency does not contain: {}", targetAddr);
                latencyScore = GlobalStates.expectedRequestNumberofEachNode[targetIndex];
            }
        }

        return latencyScore;
    }
    
    

    public static class HighPerformanceWeightedSelector {
        private final List<InetAddress> targets;
        private final double[] cumulativeWeights;
        private final AtomicLong[] selectionCounts;
        private final Random random;
    
        public HighPerformanceWeightedSelector(List<InetAddress> targets, double[] ratios) {
            if (targets.size() != ratios.length) {
                throw new IllegalArgumentException("Targets and ratios must have the same length.");
            }
            this.targets = targets;
            this.cumulativeWeights = new double[ratios.length];
            this.selectionCounts = new AtomicLong[targets.size()];
            for (int i = 0; i < targets.size(); i++) {
                selectionCounts[i] = new AtomicLong(0);
                cumulativeWeights[i] = (i == 0 ? 0 : cumulativeWeights[i - 1]) + ratios[i];
            }
            this.random = new Random();
        }
    
        public InetAddress selectTarget() {
            double rand = random.nextDouble();
            int targetIndex = Arrays.binarySearch(cumulativeWeights, rand);
            if (targetIndex < 0) {
                targetIndex = -targetIndex - 1;
            }
            selectionCounts[targetIndex].incrementAndGet();
            return targets.get(targetIndex);
        }
    
        public long[] getSelectionCounts() {
            return Arrays.stream(selectionCounts).mapToLong(AtomicLong::get).toArray();
        }
    
    }



    public static void main(String[] args) throws UnknownHostException, InterruptedException {
        List<InetAddress> targets = IntStream.range(0, 3)
                .mapToObj(i -> {
                    try {
                        return InetAddress.getByName("192.168.1." + (i + 1));
                    } catch (UnknownHostException e) {
                        throw new RuntimeException(e);
                    }
                })
                .collect(Collectors.toList());

        double[] ratios = {0.7, 0.2, 0.1};
        HighPerformanceWeightedSelector selector = new HighPerformanceWeightedSelector(targets, ratios);

        // Create thread pool to simulate concurrent selection
        ExecutorService executor = Executors.newFixedThreadPool(10);
        int totalSelections = 1000000;

        for (int i = 0; i < totalSelections; i++) {
            executor.submit(selector::selectTarget);
        }

        executor.shutdown();
        executor.awaitTermination(1, TimeUnit.MINUTES);

        // Print the results
        long[] selectionCounts = selector.getSelectionCounts();
        for (int i = 0; i < selectionCounts.length; i++) {
            System.out.printf("Target %s: %d selections (%.2f%%)%n", targets.get(i), selectionCounts[i], selectionCounts[i] * 100.0 / totalSelections);
        }
    }
    
    public static class RandomSelector
    {
        private final Random random;
        private static final List<Double> testPolicy = new ArrayList<Double>(Arrays.asList(0.5, 0.25, 0.25));
        public RandomSelector() 
        {
            this.random = new Random();
        }

        public int selectReplica(List<Double> policy) 
        {
            double rand = this.random.nextDouble();
            if(rand < policy.get(0)) 
            {
                return 0;
            }
            else if(rand < policy.get(0) + policy.get(1)) 
            {
                return 1;
            }
            else 
            {
                return 2;
            }
        }

        public int selectReplica() 
        {
            return selectReplica(testPolicy);
        }
    }
}
