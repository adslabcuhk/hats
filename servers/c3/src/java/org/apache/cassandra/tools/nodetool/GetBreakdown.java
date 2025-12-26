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
package org.apache.cassandra.tools.nodetool;

import static java.lang.String.format;
import io.airlift.airline.Arguments;
import io.airlift.airline.Command;

import java.io.PrintStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import com.google.common.collect.HashMultimap;
import com.google.common.collect.Multimap;

import org.apache.cassandra.db.ColumnFamilyStoreMBean;
import org.apache.cassandra.metrics.CassandraMetricsRegistry;
import org.apache.cassandra.tools.NodeProbe;
import org.apache.cassandra.tools.NodeTool.NodeToolCmd;


@Command(name = "getbreakdown", description = "Print the breakdown of the foreground requests")
public class GetBreakdown extends NodeToolCmd
{
    @Arguments(usage = "[<keyspace>]", description = "The keyspace name")
    private List<String> args = new ArrayList<>();

    @Override
    public void execute(NodeProbe probe)
    {
        PrintStream out = probe.output().out;
        Multimap<String, String> tablesList = HashMultimap.create();

        // a <keyspace, set<table>> mapping for verification or as reference if none provided
        Multimap<String, String> allTables = HashMultimap.create();
        Iterator<Map.Entry<String, ColumnFamilyStoreMBean>> tableMBeans = probe.getColumnFamilyStoreMBeanProxies();
        while (tableMBeans.hasNext())
        {
            Map.Entry<String, ColumnFamilyStoreMBean> entry = tableMBeans.next();
            allTables.put(entry.getKey(), entry.getValue().getTableName());
        }

        if (args.size() == 1)
        {
            String keyspace = args.get(0);
            for (String table : allTables.get(keyspace))
            {
                tablesList.put(keyspace, table);
            }
        }
        else if (args.size() == 0)
        {
            // use all tables
            tablesList = allTables;
        }
        else
        {
            throw new IllegalArgumentException("tablehistograms requires <keyspace> format argument.");
        }

        // Get the local operation latency for each table and generate the average read latency 
        for(String keyspace : tablesList.keys().elementSet())
        {
            long totalReadCount = 0;
            long totalCoordinatorReadCount = 0;
            long totalWriteCount = 0;
            long totalCoordinatorWriteCount = 0;
            long totalRangeCount = 0;
            long totalCoordinatorScanCount = 0;
            Map<String, Long> readCount = new HashMap<>();
            Map<String, Long> writeCount = new HashMap<>();
            Map<String, Long> rangeCount = new HashMap<>();
            Map<String, Double> readLatency = new HashMap<>();
            Map<String, Double> writeLatency = new HashMap<>();
            Map<String, Double> rangeLatency = new HashMap<>();
            Map<String, Long> coordinatorReadCount = new HashMap<>();
            Map<String, Double> coordinatorReadLatency = new HashMap<>();
            Map<String, Double> coordinatorScanCount = new HashMap<>();
            Map<String, Double> coordinatorScanLatency = new HashMap<>();
            Map<String, Long> coordinatorWriteCount = new HashMap<>();
            Map<String, Double> coordinatorWriteLatency = new HashMap<>();

            Map<String, Double> keyCacheHitRate = new HashMap<>();
            Map<String, Double> rowCacheHitRate = new HashMap<>();
            
            
            // Get local operation latecy of each table
            for(String table : tablesList.get(keyspace))
            {
                long tableWriteCount = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "WriteLatency")).getCount();
                long tableReadCount = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "ReadLatency")).getCount();
                long tableRangeCount = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "RangeLatency")).getCount();
                double localReadLatency = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "ReadLatency")).getMean();
                double localWriteLatency = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "WriteLatency")).getMean();
                double range_latency = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "RangeLatency")).getMean();
                long tableCoordinatorReadCount = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "CoordinatorReadLatency")).getCount();
                double coordinator_read_latency = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "CoordinatorReadLatency")).getMean();
                double tableCoordinatorScanCount = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "CoordinatorScanLatency")).getCount();
                double coordinator_scan_latency = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "CoordinatorScanLatency")).getMean();
                long tableCoordinatorWriteCount = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "CoordinatorWriteLatency")).getCount();
                double coordinator_write_latency = ((CassandraMetricsRegistry.JmxTimerMBean) probe.getColumnFamilyMetric(keyspace, table, "CoordinatorWriteLatency")).getMean();

                double keyCacheHitRateValue = ((Double) probe.getColumnFamilyMetric(keyspace, table, "KeyCacheHitRate"));
                long rowCacheHit = ((Long) probe.getColumnFamilyMetric(keyspace, table, "RowCacheHit"));
                long rowCacheMiss = ((Long) probe.getColumnFamilyMetric(keyspace, table, "RowCacheMiss"));
                double rowCacheHitRateValue = (double) rowCacheHit / (rowCacheHit + rowCacheMiss);
                
                totalReadCount += tableReadCount;
                totalWriteCount += tableWriteCount;
                totalRangeCount += tableRangeCount;
                totalCoordinatorReadCount += tableCoordinatorReadCount;
                totalCoordinatorScanCount += tableCoordinatorScanCount;
                totalCoordinatorWriteCount += tableCoordinatorWriteCount;


                readCount.put(table, tableReadCount);
                writeCount.put(table, tableWriteCount);
                rangeCount.put(table, tableRangeCount);
                coordinatorReadCount.put(table, tableCoordinatorReadCount);
                coordinatorScanCount.put(table, tableCoordinatorScanCount);
                coordinatorWriteCount.put(table, tableCoordinatorWriteCount);

                keyCacheHitRate.put(table, keyCacheHitRateValue);
                rowCacheHitRate.put(table, rowCacheHitRateValue);


                if(tableReadCount > 0 && !Double.isNaN(localReadLatency))
                {
                    readLatency.put(table, localReadLatency);
                }
                else
                {
                    readLatency.put(table, (double) 0);
                }
                if(tableWriteCount > 0 && !Double.isNaN(localWriteLatency))
                {
                    writeLatency.put(table, localWriteLatency);
                }
                else
                {
                    writeLatency.put(table, (double) 0);
                }
                if(tableRangeCount > 0 && !Double.isNaN(range_latency))
                {
                    rangeLatency.put(table, range_latency);
                }
                else
                {
                    rangeLatency.put(table, (double) 0);
                }
                if(tableCoordinatorReadCount > 0 && !Double.isNaN(coordinator_read_latency))
                {
                    coordinatorReadLatency.put(table, coordinator_read_latency);
                }
                else
                {
                    coordinatorReadLatency.put(table, (double) 0);
                }
                if(tableCoordinatorScanCount > 0 && !Double.isNaN(coordinator_scan_latency))
                {
                    coordinatorScanLatency.put(table, coordinator_scan_latency);
                }
                else
                {
                    coordinatorScanLatency.put(table, (double) 0);
                }
                if(tableCoordinatorWriteCount > 0 && !Double.isNaN(coordinator_write_latency))
                {
                    coordinatorWriteLatency.put(table, coordinator_write_latency);
                }
                else
                {
                    coordinatorWriteLatency.put(table, (double) 0);
                }
            }

            double averageLocalReadLatency = 0;
            double averageLocalWriteLatency = 0;
            double averageLocalRangeLatency = 0;
            double averageCoordiantorReadLatency = 0;
            double averageCoordiantorScanLatency = 0;
            double averageCoordiantorWriteLatency = 0;
            
            out.println(format("%-10s%10s%10s%10s%10s%10s%10s%10s%10s%10s%10s%10s%10s%10s%10s",
            "Table", "Read", "RCnt", "CorR", "CorRCnt", "Write", "WCnt", "CorW", "CorWCnt", "Scan", "SCnt", "CorS", "CorSCnt", "keyHit", "rowHit"));
            for(String table : tablesList.get(keyspace))
            { 
                
                out.println(format("%-10s%10.2f%10s%10.2f%10s%10.2f%10s%10.2f%10s%10.2f%10s%10.2f%10s%10s%10s",
                                    table, 
                                    readLatency.get(table), readCount.get(table), coordinatorReadLatency.get(table), coordinatorReadCount.get(table),
                                    writeLatency.get(table), writeCount.get(table), coordinatorWriteLatency.get(table), coordinatorWriteCount.get(table), 
                                    rangeLatency.get(table), rangeCount.get(table), coordinatorScanLatency.get(table), coordinatorScanCount.get(table),
                                    keyCacheHitRate.get(table), rowCacheHitRate.get(table)));

                averageLocalReadLatency += readLatency.get(table) * readCount.get(table) / totalReadCount;
                averageLocalWriteLatency += writeLatency.get(table) * writeCount.get(table) / totalWriteCount;
                averageLocalRangeLatency += rangeLatency.get(table) * rangeCount.get(table) / totalRangeCount;
                averageCoordiantorReadLatency += coordinatorReadLatency.get(table) * coordinatorReadCount.get(table) / totalCoordinatorReadCount;
                averageCoordiantorScanLatency += coordinatorScanLatency.get(table) * coordinatorScanCount.get(table) / totalCoordinatorScanCount;
                averageCoordiantorWriteLatency += coordinatorWriteLatency.get(table) * coordinatorWriteCount.get(table) / totalCoordinatorWriteCount;
            }
            out.println(format("Local read latency: %.2f", averageLocalReadLatency));
            out.println(format("Local read count: %d", totalReadCount));
            out.println(format("Local write latency: %.2f", averageLocalWriteLatency));
            out.println(format("Local write count: %d", totalWriteCount));
            out.println(format("Local range latency: %.2f", averageLocalRangeLatency));
            out.println(format("Local range count: %d", totalRangeCount));
            out.println(format("Coordinator read latency: %.2f", averageCoordiantorReadLatency));
            out.println(format("Coordinator read count: %d", totalCoordinatorReadCount));
            out.println(format("Coordinator scan latency: %.2f", averageCoordiantorScanLatency));
            out.println(format("Coordinator scan count: %d", totalCoordinatorScanCount));
            out.println(format("Coordinator write latency: %.2f", averageCoordiantorWriteLatency));
            out.println(format("Coordinator write count: %d", totalCoordinatorWriteCount));
            out.println();

        }


        Map<String, Long> operationBreakdown = probe.getBreakdownTime();
        out.println("Operation type breakdown (ms):");
        out.println("CoordinatorReadTime: " + operationBreakdown.get("CoordinatorReadTime"));
        out.println("CoordinatorWriteTime: " + operationBreakdown.get("CoordinatorWriteTime"));
        out.println("LocalReadTime: " + operationBreakdown.get("LocalReadTime"));
        out.println("LocalWriteTime: " + operationBreakdown.get("LocalWriteTime"));
        out.println("WriteMemTable: " + operationBreakdown.get("WriteMemTable"));
        out.println("CommitLog: " + operationBreakdown.get("CommitLog"));
        out.println("Flush: " + operationBreakdown.get("Flush"));
        out.println("Compaction: " + operationBreakdown.get("Compaction"));
        out.println("ReadCache: " + operationBreakdown.get("ReadCache"));
        out.println("ReadMemTable: " + operationBreakdown.get("ReadMemTable"));
        out.println("ReadSSTable: " + operationBreakdown.get("ReadSSTable"));
        out.println("ReadWaitTime: " + operationBreakdown.get("ReadWaitTime"));
        out.println("ActorCost: " + operationBreakdown.get("ActorCost"));
        out.println("ForwardedReadRequest: " + operationBreakdown.get("ForwardedReadRequest"));
        out.println();

        // Get messaging queuing latency
        
        String[] messageTypes = {"READ_RSP", "READ_REQ", "MUTATION_RSP", "MUTATION_REQ"};
        out.println("Print the average messaging queue wait latency for each message type:");
        for (String messageType : messageTypes)
        {
            out.println(format("Wait latency for %s: %f", messageType, probe.getMessagingQueueWaitMetrics(messageType).getMean()));
        }
        out.println();

        // Get the network operations latency
        String[] networkOperations = {"Read", "Write"};
        out.println("Print the average network operations latency for each operation type:");
        for (String operation : networkOperations)
        {
            out.println(format("Network latency for %s: %f", operation, probe.getProxyMetric(operation).getMean()));
        }

    }
}
