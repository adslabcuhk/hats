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

package org.apache.cassandra.horse.controller;

import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.horse.HorseUtils;
import org.apache.cassandra.service.StorageService;

import com.codahale.metrics.Meter;
import com.codahale.metrics.MetricRegistry;
/**
 * @author anonymous@gmail.com
 */

public class RateLimiter 
{

    private static final MetricRegistry registry = new MetricRegistry();

    public volatile static RateLimiter compactionRateLimiter = new RateLimiter(new int[] { 80, 10, 10 });

    private final ConcurrentHashMap<Integer, Integer> targetRatios;
    private final ConcurrentHashMap<Integer, AtomicInteger> servedCounts;
    private final ConcurrentHashMap<Integer, AtomicInteger> receivedCounts;
    private final int totalTasks;
    private final AtomicInteger totalServed;
    private final AtomicInteger totalReceived;
    private final Random random;

    public RateLimiter(int[] targetRatiosArray) 
    {
        this.targetRatios = new ConcurrentHashMap<>();
        this.servedCounts = new ConcurrentHashMap<>();
        this.receivedCounts = new ConcurrentHashMap<>();
        this.totalTasks = targetRatiosArray.length;
        this.totalServed = new AtomicInteger(0);
        this.totalReceived = new AtomicInteger(0);
        this.random = new Random();

        for (int i = 0; i < targetRatiosArray.length; i++) 
        {
            targetRatios.put(i, targetRatiosArray[i]);
            servedCounts.put(i, new AtomicInteger(0));
            receivedCounts.put(i, new AtomicInteger(0));
        }
    }

    public Boolean receiveTask(int taskType) 
    {
        receivedCounts.get(taskType).incrementAndGet();
        totalReceived.incrementAndGet();

        boolean shouldServe = shouldServeTask(taskType);

        if (shouldServe) 
        {
            serveTask(taskType);
            return true;
        }
        return false;
    }

    private boolean shouldServeTask(int taskType) 
    {
        if (totalServed.get() == 0) 
        {
            return true;
        }

        final double foregroundRate = StorageService.instance.coordinatorReadRateMonitor.getRateInMB() +
                                      StorageService.instance.flushRateMonitor.getRateInMB() * 2;
        final double throttleBackgroundRate = DatabaseDescriptor.getThrottleDataRate() - foregroundRate - 10;
        final double backgroundRate = StorageService.instance.compactionRateMonitor.getRateInMB();
        
        if(backgroundRate >= throttleBackgroundRate)
        {
            return false;
        }
        else if(foregroundRate < 1)
        {
            return true;
        }

        int currentCount = servedCounts.get(taskType).get() * 100;
        int targetCount = targetRatios.get(taskType) * totalServed.get();

        int allowance = (int) (0.1 * targetRatios.get(taskType) * totalReceived.get());
        return currentCount < (targetCount + allowance);
    }

    private void serveTask(int taskType) 
    {
        servedCounts.get(taskType).incrementAndGet();
        totalServed.incrementAndGet();
        // System.out.println("Served task type: " + taskType);
    }

    private void reset() 
    {
        this.totalServed.set(0);
        this.totalReceived.set(0);
        for (int i = 0; i < totalTasks; i++) 
        {
            this.servedCounts.get(i).set(0);
            this.receivedCounts.get(i).set(0);
        }
    }


    public static void updateLimiter(Double[] targetRatiosArray) 
    {
        int[] targetRatiosArrayInteger = new int[targetRatiosArray.length];
        for (int i = 0; i < targetRatiosArray.length; i++) 
        {
            targetRatiosArrayInteger[i] =  Math.max((int) (targetRatiosArray[i] * 100), 10);
        }
        compactionRateLimiter = new RateLimiter(targetRatiosArrayInteger);
    }


    private static void runRandomTaskSelectionTest(RateLimiter rateLimiter) 
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

    private static void runSimulatedTaskDistributionTest(RateLimiter rateLimiter) 
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

    private static void printFinalServedCounts(RateLimiter rateLimiter) 
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
            return HorseUtils.rounding(this.dataRate.getOneMinuteRate() / (1024L * 1024L), 3);
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