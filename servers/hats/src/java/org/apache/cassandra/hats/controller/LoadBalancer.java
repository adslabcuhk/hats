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

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.apache.cassandra.concurrent.ExecutorFactory.Global;
import org.apache.cassandra.hats.Scheduler;
import org.apache.cassandra.hats.leaderelection.election.ElectionBootstrap;
import org.apache.cassandra.hats.states.GlobalStates;
import org.apache.cassandra.hats.states.GlobalStates.LoadBalancingStrategy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class LoadBalancer {



    private static final Logger logger = LoggerFactory.getLogger(LoadBalancer.class);
    public static Double[][] balanceLoad(int N, int R, int W, double[] L, int[][] C) 
    {
        double[] requestCount = new double[N]; // request count of each node
        for (int i = 0; i < N; i++) {
            for (int j = 0; j < R; j++) {
                requestCount[i] += C[i][j];
            }
        }
        double[] latency = new double[N]; // average latency of each node
        for (int i = 0; i < N; i++) {
            latency[i] = L[i] / 1000000; // from us to seconds
        }
        double[] T = new double[N]; // The maximum number of requests that a physical core can handle within a time window W.
        for (int i = 0; i < N; i++) {
            T[i] = W / latency[i];
        }
        
        double[] lambda = new double[N]; // The number of the physical core of each node
        for (int i = 0; i < N; i++) {
            lambda[i] = 4;
        }

        double[] actualThpt = new double[N]; // The actual request count of each thread
        for (int i = 0; i < N; i++) {
            actualThpt[i] = requestCount[i] / lambda[i];
        }

        double[] targetThpt = new double[N]; // Target request count of each thread
        for (int i = 0; i < N; i++) {
            targetThpt[i] = T[i];
        }

        int[] targetCount = new int[N]; // Target request count of each node
        for (int i = 0; i < N; i++) {
            targetCount[i] = (int) (targetThpt[i] * lambda[i]);
        }

        int[][] count = new int[N][R]; // The load matrix
        for (int i = 0; i < N; i++) {
            for (int j = 0; j < R; j++) {
                count[i][j] = C[i][j];
            }
        }
        // print the average latency, service rate, and concurrency factor of each node
        System.out.println("Average latency (us) of each node:");
        System.out.println(Arrays.toString(L));
        System.out.println("Request count of each node:");
        System.out.println(Arrays.toString(requestCount));
        System.out.println("Target request count of each node:");
        System.out.println(Arrays.toString(targetCount));
        System.out.println("Actual thpt (ops/threads) of each node:");
        System.out.println(Arrays.toString(actualThpt));
        System.out.println("Target thoughput (service rate) of each node:");
        System.out.println(Arrays.toString(targetThpt));
        System.out.println("Concurrency factor of each node:");
        System.out.println(Arrays.toString(lambda));



        Double[][] readRatio = new Double[N][R];
        int maxIter = 1;

        for (int iter = 0; iter < maxIter; iter++)
        {
            int[] actualCountOfEachNode = new int[N];
            int[] actualCountOfEachReplicationGroup = new int[N];
            int[] deltaVector = new int[N];

            // initialize actualCountOfEachNode based on C
            for (int i = 0; i < N; i++) {
                for (int j = 0; j < R; j++) {
                    actualCountOfEachNode[i] += count[i][j];
                }
            }
            for (int i = 0; i < N; i++) {
                deltaVector[i] = targetCount[i] - actualCountOfEachNode[i];
            }


            // Traverse all nodes
            for (int i = 0; i < N; i++) {
                // Get the indices of the nodes with positive and negative delta
                List<Integer> positiveIndices = new ArrayList<>(); // light load nodes
                List<Integer> negativeIndices = new ArrayList<>(); // overload nodes

                for (int j = 0; j < R; j++) {
                    int neighborIndex = (i + j) % N;
                    if (deltaVector[neighborIndex] > 0) {
                        positiveIndices.add(j); // positive value: light nodes
                    } else if (deltaVector[neighborIndex] < 0) {
                        negativeIndices.add(j); // negative value: overload nodes
                    }
                }

                // move requests from overloaded nodes to light load nodes
                for (int neg : negativeIndices)
                {
                    int nodeIndexNeg = (i + neg) % N; 
                    for (int pos : positiveIndices) {
                        int nodeIndexPos = (i + pos) % N; 
                        int adjustment = Math.min(-deltaVector[nodeIndexNeg], deltaVector[nodeIndexPos]);
                        adjustment = Math.min(adjustment, count[nodeIndexNeg][neg]);

                        count[nodeIndexNeg][neg] -= adjustment; 
                        count[nodeIndexPos][pos] += adjustment; 

                        deltaVector[nodeIndexNeg] += adjustment;
                        deltaVector[nodeIndexPos] -= adjustment;

                        if (deltaVector[nodeIndexPos] == 0) {
                            break;
                        }
                    }
                }

                // update actualCountOfEachNode
                for (int j = 0; j < R; j++) {
                    int nodeIndex = (i + j) % N;
                    actualCountOfEachNode[nodeIndex] = 0;

                    // update actualCountOfEachNode
                    for (int k = 0; k < R; k++) {
                        actualCountOfEachNode[nodeIndex] += count[nodeIndex][k];
                    }

                    // update estimate latency latency[i]
                    latency[nodeIndex] = lambda[nodeIndex] * W / actualCountOfEachNode[nodeIndex];
                    // latency[nodeIndex] =  W / actualCountOfEachNode[nodeIndex];
                    actualCountOfEachReplicationGroup[i] += count[nodeIndex][j];
                }
            }
            // Calculate the read ratio of each replication group
            for (int i = 0; i < N; i++) {
                for (int j = 0; j < R; j++) {
                    readRatio[i][j] = count[i][j] * 1.0 / actualCountOfEachReplicationGroup[(i - j + N) % N];
                }
            }
            GlobalStates.expectedStates = new LoadBalancingStrategy(ElectionBootstrap.getLeaderTerm(), Scheduler.version.incrementAndGet(), count);

            // print the throughput of each node
            System.out.println("Throughput of each node:");
            for (int i = 0; i < N; i++) {
                System.out.printf("%10.2f ", actualCountOfEachNode[i] / lambda[i]);
            }

            
            // Print the transposed request count matrix
            logger.info("Transposed request count matrix:");
            for (int i = 0; i < R; i++) {
                StringBuilder row = new StringBuilder();
                for (int j = 0; j < N; j++) {
                    row.append(String.format("%10d ", count[j][i]));  // Format as integer with width 10
                }
                logger.info(row.toString());  // Log the entire row at once
            }

            // Print the transposed read ratio matrix
            logger.info("Transposed read ratio matrix:");
            for (int i = 0; i < R; i++) {
                StringBuilder row = new StringBuilder();
                for (int j = 0; j < N; j++) {
                    row.append(String.format("%10.2f ", readRatio[j][i]));  // Format as float with width 10 and 2 decimal places
                }
                logger.info(row.toString());  // Log the entire row at once
            }
        }

        return readRatio;
    }



    public static void main(String[] args) {
        int N = 10; // node number
        int R = 3; // replication factor

        int W = 60; // time window size, 60 seconds

        double[] L = {1142, 1693, 1754, 1140, 1189, 1973, 4085, 1474, 1917, 1067}; // average latency of each node

        // Request count of each replication group on each node
        // double[][] C = {
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0},
        //     {100000, 0, 0}
        // };

        int[][] C = {
            {136351, 2130, 2209},
            {184210, 21335, 0},
            {151762, 37900, 10744},
            {151395, 5, 0},
            {180295, 3, 22182},
            {146113, 32150, 20422},
            {106165, 6968, 9120},
            {140929, 68745, 0},
            {132060, 25434, 12332},
            {157912, 17642, 0}
        };


        // print the transposed request count matrix
        System.out.println("Transposed request count matrix:");
        for (int i = 0; i < R; i++) {
            for (int j = 0; j < N; j++) {
                System.out.printf("%10d ", C[j][i]);
            }
            System.out.println();
        }

        Double[][] readRatio = balanceLoad(N, R, W, L, C);

        // // Print the transposed request count matrix
        // System.out.println("Transposed request count matrix:");
        // for (int i = 0; i < R; i++) {
        //     for (int j = 0; j < N; j++) {
        //         System.out.printf("%10d ", C[j][i]);
        //     }
        //     System.out.println();
        // }

        // // Print the transposed read ratio matrix
        // System.out.println("Transposed read ratio matrix:");
        // for (int i = 0; i < R; i++) {
        //     for (int j = 0; j < N; j++) {
        //         System.out.printf("%10.2f ", readRatio[j][i]);
        //     }
        //     System.out.println();
        // }
    }
}
