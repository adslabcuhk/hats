/*
 *      Copyright (C) 2012-2015 DataStax Inc.
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */
package com.datastax.driver.core;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.codahale.metrics.MetricRegistry;
import com.codahale.metrics.SlidingTimeWindowReservoir;
import com.codahale.metrics.Timer;

public class HatsUtils 
{
    private static final Logger logger = LoggerFactory.getLogger(HatsUtils.class);

    private final static MetricRegistry registry = new MetricRegistry();
    public enum QueryType
    {
        READ,
        INSERT,
        UPDATE,
        SCAN,
        DELETE
    }

    public enum HatsLogLevels 
    {
        TRACE, 
        DEBUG, 
        INFO, 
        WARN, 
        ERROR
    }

    public static class StatesForClients implements Serializable
    {
        final Map<String, List<Double>> policy;
        final Map<InetAddress, Double> coordinatorReadLatency;
        final Map<InetAddress, Double> readLatency = new HashMap<>();
        final double coordinatorWeight;
        
        public StatesForClients(Map<String, List<Double>> policy, Map<InetAddress, Double> coordinatorReadLatency, ConcurrentHashMap<InetAddress, HatsLatencyTracker> readLatencyTrackers)
        {
            this.policy = policy;
            this.coordinatorReadLatency = coordinatorReadLatency;


            long totalReadCount = 0;
            double averageReadLatency = 0.0;
            double averageCoordinatorLatency = 0.0;

            for (Map.Entry<InetAddress, HatsLatencyTracker> entry : readLatencyTrackers.entrySet())
            {
                this.readLatency.put(entry.getKey(), entry.getValue().getLatencyForLocalStates());
                totalReadCount += entry.getValue().getCount();
            }

            for(Map.Entry<InetAddress, HatsLatencyTracker> entry : readLatencyTrackers.entrySet())
            {
                averageReadLatency = (entry.getValue().getCount() * 1.0 / totalReadCount) * this.readLatency.get(entry.getKey());
                averageCoordinatorLatency = (entry.getValue().getCount() * 1.0 / totalReadCount) * this.coordinatorReadLatency.get(entry.getKey());
            } 
            // calculate the cov of the read latency
            double sum = 0.0;
            for (Map.Entry<InetAddress, HatsLatencyTracker> entry : readLatencyTrackers.entrySet())
            {
                sum += Math.pow(this.coordinatorReadLatency.get(entry.getKey()) - averageCoordinatorLatency, 2);
            }
            double cov = Math.sqrt(sum / totalReadCount) / averageCoordinatorLatency;

            // TODO recalculate the coordinator weight for each replication group
            this.coordinatorWeight = averageCoordinatorLatency / averageReadLatency;
            logger.info("HATSInfo: the average coordinator read latency across all nodes is {}, the cov is {}", averageCoordinatorLatency, cov);

        }
    }

    public static class HatsLatencyTracker
    {
        private final Timer timer;

        public HatsLatencyTracker(String metricName, int windowInterval) {
            this.timer = new Timer(new SlidingTimeWindowReservoir(windowInterval, TimeUnit.SECONDS));
            registry.register(metricName, this.timer);
        }

        public void update(long latency) {
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
            // return getMedian();
            return getWindowMean();
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

    public static void printStackTace(HatsLogLevels logLevel, String msg) 
    {
        if (logLevel.equals(HatsLogLevels.DEBUG))
            logger.debug("stack trace {}", new Exception(msg));
        if (logLevel.equals(HatsLogLevels.ERROR))
            logger.error("stack trace {}", new Exception(msg));
        if (logLevel.equals(HatsLogLevels.INFO))
            logger.info("stack trace {}", new Exception(msg));
    }

    public static class ByteObjectConversion 
    {
        public static byte[] objectToByteArray(Serializable obj) throws IOException 
        {
            logger.debug("HATS-Debug: start to transform");
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            ObjectOutputStream oos = new ObjectOutputStream(bos);
            oos.writeObject(obj);
            oos.flush();
            oos.close();
            bos.close();
            return bos.toByteArray();
        }

        public static Object byteArrayToObject(byte[] bytes) throws Exception 
        {
            ByteArrayInputStream bis = new ByteArrayInputStream(bytes);
            ObjectInputStream ois = new ObjectInputStream(bis);
            Object obj = ois.readObject();
            bis.close();
            ois.close();
            return obj;
        }
    }

    public static class HatsReplicaSelector 
    {
        private final List<Host> targets;
        private final int[] cumulativeWeights;
        private final AtomicLong[] selectionCounts;
        private final int totalWeight;
        public final AtomicLong totalSelections;

        public HatsReplicaSelector(List<Host> targets, List<Double> ratios) 
        {
            if (targets.size() != ratios.size()) {
                throw new IllegalArgumentException("Targets and ratios must have the same length.");
            }
            this.targets = targets;
            this.cumulativeWeights = new int[ratios.size()];
            this.selectionCounts = new AtomicLong[targets.size()];
    
            int cumulativeSum = 0;
            for (int i = 0; i < targets.size(); i++) {
                cumulativeSum += (int)(ratios.get(i) * 100000);  // Scale to avoid floating point issues
                cumulativeWeights[i] = cumulativeSum;
                selectionCounts[i] = new AtomicLong(0);
            }
            this.totalWeight = cumulativeSum;
            this.totalSelections = new AtomicLong(0);
        }
    
        public Host selectTarget() {
            int rand = ThreadLocalRandom.current().nextInt(totalWeight);
            int targetIndex = Arrays.binarySearch(cumulativeWeights, rand);
            if (targetIndex < 0) {
                targetIndex = -targetIndex - 1;
            }
            selectionCounts[targetIndex].incrementAndGet();
            totalSelections.incrementAndGet();
            return targets.get(targetIndex);
        }
    
        public long[] getSelectionCounts() {
            return Arrays.stream(selectionCounts).mapToLong(AtomicLong::get).toArray();
        }
    }
    public static class HatsReplicaSelectorTest {
        private final List<InetAddress> targets;
        private final int[] cumulativeWeights;
        private final AtomicLong[] selectionCounts;
        private final int totalWeight;
    
        public HatsReplicaSelectorTest(List<InetAddress> targets, List<Double> ratios) {
            if (targets.size() != ratios.size()) {
                throw new IllegalArgumentException("Targets and ratios must have the same length.");
            }
            this.targets = targets;
            this.cumulativeWeights = new int[ratios.size()];
            this.selectionCounts = new AtomicLong[targets.size()];
    
            int cumulativeSum = 0;
            for (int i = 0; i < targets.size(); i++) {
                cumulativeSum += (int)(ratios.get(i) * 100000);  // Scale to avoid floating point issues
                cumulativeWeights[i] = cumulativeSum;
                selectionCounts[i] = new AtomicLong(0);
            }
            this.totalWeight = cumulativeSum;
        }
    
        public InetAddress selectTarget() {
            int rand = ThreadLocalRandom.current().nextInt(totalWeight);
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
    public static void main(String[] args) throws UnknownHostException, InterruptedException 
    {
        List<InetAddress> targets = IntStream.range(0, 3)
                .mapToObj(i -> {
                    try {
                        return InetAddress.getByName("192.168.1." + (i + 1));
                    } catch (UnknownHostException e) {
                        // TODO Auto-generated catch block
                        e.printStackTrace();
                    }
                    // return new Host(InetSocketAddress.createUnresolved("192.168.1." + (i + 1), 7000), new ConvictionPolicy.DefaultConvictionPolicy.Factory(), null);
                    return null;
                })
                .collect(Collectors.toList());
        // double[] ratios = {0.7, 0.2, 0.1};
        List<Double> ratios = Arrays.asList(0.9655987904308467, 0.03440120956915328, 0.0);
        HatsReplicaSelectorTest selector = new HatsReplicaSelectorTest(targets, ratios);

        // Create thread pool to simulate concurrent selection
        ExecutorService executor = Executors.newFixedThreadPool(10);
        int totalSelections = 1000;

        for (int i = 0; i < totalSelections; i++) 
        {
            executor.submit(selector::selectTarget);
        }

        executor.shutdown();
        executor.awaitTermination(1, TimeUnit.MINUTES);

        // Print the results
        long[] selectionCounts = selector.getSelectionCounts();
        for (int i = 0; i < selectionCounts.length; i++) 
        {
            System.out.printf("Target %s: %d selections (%.2f%%)%n", targets.get(i), selectionCounts[i], selectionCounts[i] * 100.0 / totalSelections);
        }
    }



    public static class LoadBalancer {
        public static void main(String[] args) {
            long[] requests = {147210, 186375, 147838, 197073, 130805, 165453, 145773, 136649}; // 示例输入
            long[][] result = balanceLoad(requests);

            System.out.println(String.format("The average count is %s, the total count is %s", Arrays.stream(requests).sum() / requests.length, Arrays.stream(requests).sum()));

            long sumAfterAlg = 0;
            for (int i = 0; i < result.length; i++) {
                System.out.println("Node " + i + ": " + Arrays.toString(result[i]) + "   " + Arrays.stream(result[i]).sum());
                sumAfterAlg += requests[i];
            }
            System.out.println("Sum after algorithm: " + sumAfterAlg);
        }

        public static long[][] balanceLoad(long[] requests) {
            int n = requests.length;
            long totalRequests = Arrays.stream(requests).sum();
            long averageRequests = totalRequests / n;
            long threshold = (long) (averageRequests * 1.00);
            int rf = 3; // replication factor
    
            long[][] result = new long[n][3];
    
            // Initialize result array
            for (int i = 0; i < n; i++) {
                result[i][0] = requests[i];
            }
    
            // Distribute requests
            for (int i = 0; i < n; i++) {
                long excess = result[i][0] - threshold;
                if (excess > 0) {
                    for(int j = 0; j < rf && excess > 0; j++) {
                        if (excess == 0) {
                            break;
                        }
                        
                        int index = (i + j) % n;
                        if(requests[index] < threshold)
                        {
                            // long capacity = threshold - requests[index];
                            long capacity = requests[i] - (requests[i] + requests[index]) / 2;
                            long offload = Math.min(capacity, excess);
                            requests[i] -= offload;
                            requests[index] += offload;
                            result[i][0] -= offload;
                            result[index][j] += offload;
                            excess -= offload;
                        }
                    }
                }
            }
    
            return result;
        }
    }

}
