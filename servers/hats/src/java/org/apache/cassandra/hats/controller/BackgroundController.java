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

import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.hats.HatsUtils;
import org.apache.cassandra.service.StorageService;

import com.codahale.metrics.Meter;
import com.codahale.metrics.MetricRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
/**
 * @author anonymous@gmail.com
 */

public class BackgroundController 
{
    private static final int INITIAL_THROTTLE_THPT = 10;
    private static final Logger logger = LoggerFactory.getLogger(BackgroundController.class);
    private static final MetricRegistry registry = new MetricRegistry();

    public volatile static BackgroundController compactionRateLimiter = new BackgroundController(new int[DatabaseDescriptor.getReplicationFactor()]);

    public volatile int throttleCompactionThroughput = DatabaseDescriptor.getCompactionThroughputMebibytesPerSecAsInt(); // MB per second 

    private final ConcurrentHashMap<Integer, Integer> targetRatios;
    private final ConcurrentHashMap<Integer, AtomicInteger> servedCounts;
    private final ConcurrentHashMap<Integer, AtomicLong> servedThpt;
    private final AtomicLong totalServedThpt;
    private final ConcurrentHashMap<Integer, AtomicInteger> receivedCounts;
    private final int totalTasks;
    private final AtomicInteger totalServedCount;
    private final AtomicInteger totalReceivedCount;
    private final Random random;

    public BackgroundController(int[] targetRatiosArray) 
    {
        this.targetRatios = new ConcurrentHashMap<>();
        this.servedCounts = new ConcurrentHashMap<>();
        this.receivedCounts = new ConcurrentHashMap<>();
        this.totalTasks = targetRatiosArray.length;
        this.totalServedCount = new AtomicInteger(0);
        this.totalReceivedCount = new AtomicInteger(0);
        this.servedThpt = new ConcurrentHashMap<>();
        this.totalServedThpt = new AtomicLong(0);
        this.random = new Random();

        targetRatiosArray[0] = 100;
        for (int i = 1; i < DatabaseDescriptor.getReplicationFactor(); i++) 
        {
            targetRatiosArray[i] = 0;
        }
    

        for (int i = 0; i < targetRatiosArray.length; i++) 
        {
            targetRatios.put(i, targetRatiosArray[i]);
            servedCounts.putIfAbsent(i, new AtomicInteger(0));
            receivedCounts.putIfAbsent(i, new AtomicInteger(0));
            servedThpt.putIfAbsent(i, new AtomicLong(0));
        }
    }

    public void updatePolicy(int[] targetRatiosArray) 
    {
        for (int i = 0; i < targetRatiosArray.length; i++) 
        {
            targetRatios.put(i, targetRatiosArray[i]);
        }
    }

    public void recordServedThpt(int taskType, long dataSize) 
    {
        servedThpt.get(taskType).addAndGet(dataSize);
        totalServedThpt.addAndGet(dataSize);
    }

    public Boolean receiveTask(int taskType) 
    {
        receivedCounts.get(taskType).incrementAndGet();
        totalReceivedCount.incrementAndGet();

        boolean shouldServe = shouldServeTask(taskType);

        if (shouldServe) 
        {
            serveTask(taskType);
            return true;
        }
        return false;
    }

    public synchronized void increaseThrottleThpt()
    {
        if (throttleCompactionThroughput < DatabaseDescriptor.getCompactionThroughputMebibytesPerSec())
            throttleCompactionThroughput += 0.05 * DatabaseDescriptor.getCompactionThroughputMebibytesPerSec();
    }

    public synchronized void decreaseThrottleThpt()
    {
        if (throttleCompactionThroughput >= 2) {
            throttleCompactionThroughput /= 2;
        }
    }

    public synchronized void updateThrottleThpt()
    {
        // TODO
        if(isBottleneck())
        {
            decreaseThrottleThpt();
            StorageService.instance.isPendingFlushHappen.set(false);
            StorageService.instance.isReadSlow.set(false);
        }
        else
        {
            increaseThrottleThpt();
        }
    }

    private boolean isBottleneck()
    {
        logger.info("HATSInfo: the throttle throughput is {}, isPendingFlushHappen {}, the total pending flushes is {}, current compaction rate is {}, is read slow happen {}",
                    throttleCompactionThroughput, 
                    StorageService.instance.isPendingFlushHappen.get(), 
                    StorageService.instance.totalPendingFlushes.get(), 
                    StorageService.instance.compactionRateMonitor.getRateInMB(), 
                    StorageService.instance.isReadSlow.get());
        return StorageService.instance.isPendingFlushHappen.get() || 
               StorageService.instance.totalPendingFlushes.get() > 0;
    }

    private boolean shouldServeTask(int taskType)
    {
        // final double foregroundRate = StorageService.instance.coordinatorReadRateMonitor.getRateInMB() +
        //                               StorageService.instance.localReadRateMonitor.getRateInMB() +
        //                               StorageService.instance.flushRateMonitor.getRateInMB() * 3;
        // final double throttleBackgroundRate = DatabaseDescriptor.getThrottleDataRate() - foregroundRate - 10;

        // if(foregroundRate < 1)
        // {
        //     return true;
        // }
        if(isBottleneck() || 
           StorageService.instance.compactionRateMonitor.getRateInMB() >= throttleCompactionThroughput)
        {
            if(StorageService.instance.totalPendingFlushes.get() < 1)
                StorageService.instance.isPendingFlushHappen.set(false);
            return false;
        }

        boolean shouldServeTaskByCount = shouldServeTaskByCount(taskType);
        boolean shouldServeTaskByThpt = shouldServeTaskByThpt(taskType);

        logger.info("HATSInfo: shouldServeTaskByCount is {}, shouldServeTaskByThpt is {}", shouldServeTaskByCount, shouldServeTaskByThpt);

        return shouldServeTaskByCount && shouldServeTaskByThpt;
    }

    private boolean shouldServeTaskByThpt(int taskType) 
    {
        if(StorageService.instance.compactionRateMonitor.getRateInMB() < INITIAL_THROTTLE_THPT)
            return true;
        long currentThpt = servedThpt.get(taskType).get() * 100;
        long targetThpt = targetRatios.get(taskType) * totalServedThpt.get();

        return currentThpt <= targetThpt;
    }

    private boolean shouldServeTaskByCount(int taskType) 
    {
        int currentCount = servedCounts.get(taskType).get() * 100;
        int targetCount = targetRatios.get(taskType) * totalServedCount.get();

        int allowance = (int) (0.1 * targetRatios.get(taskType) * totalReceivedCount.get());
        return currentCount < (targetCount + allowance);
    }

    private void serveTask(int taskType) 
    {
        servedCounts.get(taskType).incrementAndGet();
        totalServedCount.incrementAndGet();
    }

    private void reset() 
    {
        this.totalServedCount.set(0);
        this.totalReceivedCount.set(0);
        for (int i = 0; i < totalTasks; i++) 
        {
            this.servedCounts.get(i).set(0);
            this.receivedCounts.get(i).set(0);
            this.servedThpt.get(i).set(0);
        }
    }


    public static void updateLimiter(Double[] targetRatiosArray) 
    {
        int[] targetRatiosArrayInteger = new int[targetRatiosArray.length];
        for (int i = 0; i < targetRatiosArray.length; i++) 
        {
            targetRatiosArrayInteger[i] =  Math.max((int) (targetRatiosArray[i] * 100), 10);
        }
        compactionRateLimiter.updatePolicy(targetRatiosArrayInteger);
    }


    private static void runRandomTaskSelectionTest(BackgroundController rateLimiter) 
    {
        int numThreads = 10;
        Thread[] threads = new Thread[numThreads];
        for (int t = 0; t < numThreads; t++) 
        {
            threads[t] = new Thread(() -> {
                for (int i = 0; i < 100; i++) 
                {
                    int taskType = rateLimiter.random.nextInt(3);
                    rateLimiter.receiveTask(taskType);
                }
            });
        }

        for (Thread thread : threads) 
        {
            thread.start();
        }

        for (Thread thread : threads) 
        {
            try 
            {
                thread.join();
            } 
            catch (InterruptedException e) 
            {
                e.printStackTrace();
            }
        }

        printFinalServedCounts(rateLimiter);
    }

    private static void runSimulatedTaskDistributionTest(BackgroundController rateLimiter) 
    {
        int numThreads = 10;
        double[] probabilities = {0.1, 0.45, 0.45};
        Thread[] threads = new Thread[numThreads];
        for (int t = 0; t < numThreads; t++) 
        {
            threads[t] = new Thread(() -> {
                for (int i = 0; i < 100; i++) 
                {
                    int taskType = getTaskTypeByProbability(probabilities, rateLimiter.random);
                    rateLimiter.receiveTask(taskType);
                }
            });
        }

        for (Thread thread : threads) 
        {
            thread.start();
        }

        for (Thread thread : threads) 
        {
            try 
            {
                thread.join();
            } 
            catch (InterruptedException e) 
            {
                e.printStackTrace();
            }
        }

        printFinalServedCounts(rateLimiter);
    }

    private static int getTaskTypeByProbability(double[] probabilities, Random random) 
    {
        double p = random.nextDouble();
        double cumulativeProbability = 0.0;
        for (int i = 0; i < probabilities.length; i++) 
        {
            cumulativeProbability += probabilities[i];
            if (p <= cumulativeProbability) 
            {
                return i;
            }
        }
        return probabilities.length - 1; // Fallback in case of rounding errors
    }

    private static void printFinalServedCounts(BackgroundController rateLimiter) 
    {
        System.out.println("Final served counts:");
        for (int i = 0; i < rateLimiter.totalTasks; i++) 
        {
            System.out.println("Task type " + i + ": " + rateLimiter.servedCounts.get(i).get() + "/" + rateLimiter.receivedCounts.get(i).get());
        }
    }



    public static class RateMonitor
    {
        private final Meter dataRate;

        public RateMonitor(String metricName) 
        {
            this.dataRate = new Meter();
            registry.register(metricName, this.dataRate);
        }

        public void record(long dataSize) 
        {
            this.dataRate.mark(dataSize);
        }

        public double getRate() 
        {
            return this.dataRate.getOneMinuteRate();
        }

        public double getRateInMB() 
        {
            return HatsUtils.rounding(this.dataRate.getOneMinuteRate() / (1024L * 1024L), 3);
        }
    }

    public static void main(String[] args) 
    {
        // int[] targetRatios = {80, 10, 10};
        // RateLimiter rateLimiter = new RateLimiter(targetRatios);

        System.out.println("Test case 1: Random task selection");
        runRandomTaskSelectionTest(compactionRateLimiter);

        compactionRateLimiter.reset();

        System.out.println("Test case 2: Simulate task type 0 exhaustion");
        runSimulatedTaskDistributionTest(compactionRateLimiter);
    }
}