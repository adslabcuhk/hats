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
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.TimeUnit;

import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.horse.HorseUtils;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.utils.FBUtilities;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.codahale.metrics.Histogram;
import com.codahale.metrics.MetricRegistry;
import com.codahale.metrics.SlidingTimeWindowReservoir;
import com.codahale.metrics.Timer;


/**
 * @author anonymous@gmail.com
 */

public class LocalStates implements Serializable {
    private static final Logger logger = LoggerFactory.getLogger(LocalStates.class);
    private static final double ALPHA = 0.9;
    public static ConcurrentHashMap<InetAddressAndPort, Map<InetAddressAndPort, Double>> localPolicyWithAddress = new ConcurrentHashMap<>();
    public static ConcurrentHashMap<InetAddressAndPort, List<Double>> localPolicy = new ConcurrentHashMap<>();
    public final double latency; // micro second
    public final Map<InetAddress, Integer> completedReadRequestCount;
    public final int version;
    private final static MetricRegistry registry = new MetricRegistry();

    public LocalStates(Map<InetAddress, Integer> completedReadRequestCount, double latency, int version)
    {
        this.completedReadRequestCount = completedReadRequestCount;
        this.latency = latency;
        this.version = version;
    }

    public static void updateLocalPolicy()
    {
        logger.info("HATSInfo: the old local policy is {}, the local served request count is {}", localPolicy, StorageService.instance.readCounterOfEachReplica.getCompletedRequestsOfEachReplica());

        int nodeIndex = Gossiper.getAllHosts().indexOf(FBUtilities.getBroadcastAddressAndPort());
        int nodeCount = Gossiper.getAllHosts().size();

        for(int i = nodeIndex - 2; i <= nodeIndex + 2; i++)
        {
            int rgIndex = (i + nodeCount) % nodeCount;
            Map<InetAddressAndPort, Double> policyWithPort = new HashMap<>();
            List<Double> policy = new ArrayList<>();
            InetAddressAndPort rg = Gossiper.getAllHosts().get(rgIndex);
            for(int curNodeIndex = rgIndex; curNodeIndex < rgIndex + 3; curNodeIndex++)
            {
                int replicaIndex = HorseUtils.getReplicaIndexForRGInEachNode(rgIndex, curNodeIndex);
                policy.add(GlobalStates.globalPolicy[curNodeIndex % nodeCount][replicaIndex]);
                policyWithPort.put(Gossiper.getAllHosts().get(curNodeIndex % nodeCount), 
                           GlobalStates.globalPolicy[curNodeIndex % nodeCount][replicaIndex]);
            }
            localPolicyWithAddress.put(rg, policyWithPort);
            localPolicy.put(rg, policy);
        }

        logger.info("HATSInfo: We get the global placement policy {}, the local placement policy {}, with address {}", GlobalStates.globalPolicy, localPolicy, localPolicyWithAddress);
    }

    public String toString()
    {
        String requests = "";

        for (InetAddress ip : this.completedReadRequestCount.keySet())
        {
            requests += ip.getHostAddress() + ":" + this.completedReadRequestCount.get(ip) + ",";
            // requests += ip.getHostName() + ": " + readCounter.getCounter().get(ip).size() + ",";
        }
        return String.format("LocalStates{Latency=%f | Requests=%s | Version=%d}", this.latency, requests, this.version);
    }

    public static LocalStates fromString(String str, int version)
    {
        String[] metrics = str.split(" \\| ");
        if (metrics.length != 3)
        {
            throw new IllegalArgumentException(String.format("HATSERROR: wrong parsing for the string %s", str));
        }

        double latency = Double.parseDouble(metrics[0].split("=")[1].trim());
        // int version = Integer.parseInt(metrics[2].split("=")[1]);

        if(Double.isNaN(latency))
            return null;
        Map<InetAddress, Integer> completedReadRequestCount = new HashMap<>();
        String[] requestParts = metrics[1].split("=");
        if (requestParts.length < 2) 
        {
            return null;
        }
        String requests = requestParts[1];
        String[] replicationGroupRequests = requests.split(",");
        for (String request : replicationGroupRequests)
        {
            String[] kv = request.split(":");
            try {
                completedReadRequestCount.put(InetAddress.getByName(kv[0]), Integer.parseInt(kv[1]));
            } catch (NumberFormatException | UnknownHostException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            }
        }

        logger.debug("HATSDebug: the load str is {}, the parsed latency is {}, the requests are {}, the version is {}", str, latency, completedReadRequestCount, version);

        return new LocalStates(completedReadRequestCount, latency, version);
    }

    public static class ReplicaRequestCounter
    {
        private final long intervalMillis;
        private final ConcurrentHashMap<InetAddress, ConcurrentLinkedQueue<Long>> requestsPerReplica;
        private Map<InetAddress, Integer> completedRequestsOfEachReplica;
    
        public ReplicaRequestCounter(long intervalMillis) {
            this.intervalMillis = intervalMillis;
            this.requestsPerReplica = new ConcurrentHashMap<>();
        }
    
        public void mark(InetAddress ip) {
            long currentTime = System.currentTimeMillis();
            ConcurrentLinkedQueue<Long> timestamps = this.requestsPerReplica.computeIfAbsent(ip, k -> new ConcurrentLinkedQueue<>());
            timestamps.add(currentTime);
            // cleanupOldRequests(ip);
        }
    
        private int getCount(InetAddress ip) {
            cleanupOldRequests(ip);
            ConcurrentLinkedQueue<Long> timestamps = this.requestsPerReplica.get(ip);
            return timestamps != null ? timestamps.size() : 0;
        }
    
        private void cleanupOldRequests(InetAddress ip) {
            Queue<Long> timestamps = this.requestsPerReplica.get(ip);
            if (timestamps != null) {
                long cutoffTime = System.currentTimeMillis() - this.intervalMillis;
                while (!timestamps.isEmpty() && timestamps.peek() < cutoffTime) {
                    timestamps.poll();
                }
            }
        }

        public Map<InetAddress, Integer> getCompletedRequestsOfEachReplica() {
            this.completedRequestsOfEachReplica = new HashMap<>();
            for (InetAddress ip : this.requestsPerReplica.keySet())
            {
                this.completedRequestsOfEachReplica.put(ip, this.getCount(ip));
            }
            return this.completedRequestsOfEachReplica;
        }
    }


    public static class LatencyCalculator 
    {
        private final Timer timer;

        public LatencyCalculator(String metricName, int windowInterval) {
            this.timer = new Timer(new SlidingTimeWindowReservoir(windowInterval, TimeUnit.SECONDS));
            registry.register(metricName, this.timer);
        }

        public void record(long latency) {
            this.timer.update(latency, TimeUnit.MICROSECONDS);
        }

        public double getStdDev() {
            return this.timer.getSnapshot().getStdDev() / 1000L;
        }

        public double getWindowMean() 
        {
            return this.timer.getSnapshot().getMean() / 1000L;
        }

        public double getLatencyForLocalStates()
        {
            // return get75th();
            return getMedian();
            // return getWindowMean();
        }

        public double getMedian()
        {
            return this.timer.getSnapshot().getMedian() / 1000L;
        }

        public double get75th()
        {
            return this.timer.getSnapshot().get75thPercentile() / 1000L;
        }

        public double get95th()
        {
            return this.timer.getSnapshot().get95thPercentile() / 1000L;
        }

        public int getCount()
        {
            return this.timer.getSnapshot().size();
        }
    }
}
