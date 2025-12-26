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

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.TimeUnit;

import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.utils.FBUtilities;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


import org.apache.cassandra.concurrent.ScheduledExecutors;
import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.*;


// import static org.apache.cassandra.config.CassandraRelevantProperties.BROADCAST_INTERVAL_MS;

public class LocalStatesBroadcaster implements IEndpointStateChangeSubscriber
{
    static final int BROADCAST_INTERVAL_MS = 10000;

    public static final LocalStatesBroadcaster instance = new LocalStatesBroadcaster();

    private static final Logger logger = LoggerFactory.getLogger(LocalStatesBroadcaster.class);

    private ConcurrentMap<InetAddressAndPort, String> foregroundLoadInfo = new ConcurrentHashMap<>();

    private LocalStatesBroadcaster()
    {
        Gossiper.instance.register(this);
    }

    public void onChange(InetAddressAndPort endpoint, ApplicationState state, VersionedValue value)
    {
        if (state != ApplicationState.FOREGROUND_LOAD)
            return;
        foregroundLoadInfo.put(endpoint, value.value);
    }

    public void onJoin(InetAddressAndPort endpoint, EndpointState epState)
    {
        VersionedValue localValue = epState.getApplicationState(ApplicationState.FOREGROUND_LOAD);
        if (localValue != null)
        {
            onChange(endpoint, ApplicationState.FOREGROUND_LOAD, localValue);
        }
    }

    public void onRemove(InetAddressAndPort endpoint)
    {
        foregroundLoadInfo.remove(endpoint);
    }

    public void startBroadcasting()
    {
        // send the first broadcast "right away" (i.e., in 2 gossip heartbeats, when we should have someone to talk to);
        // after that send every BROADCAST_INTERVAL.
        Runnable runnable = new Runnable()
        {
            public void run()
            {
                if (!Gossiper.instance.isEnabled())
                    return;
                if (logger.isTraceEnabled())
                    logger.trace("Disseminating load info ...");
                
                double linearLatency = StorageService.instance.readLatencyCalculator.getWindowMean() * 
                                       DatabaseDescriptor.getReadSensitiveFactor() +
                                       StorageService.instance.writeLatencyCalculator.getWindowMean() * 
                                       (1 - DatabaseDescriptor.getReadSensitiveFactor());
                int version = 0;
                if(Gossiper.instance.endpointStateMap.get(FBUtilities.getBroadcastAddressAndPort()).getApplicationState(ApplicationState.FOREGROUND_LOAD) != null)
                {
                    version = Gossiper.instance.endpointStateMap
                                      .get(FBUtilities.getBroadcastAddressAndPort())
                                      .getApplicationState(ApplicationState.FOREGROUND_LOAD)
                                      .version;
                }
                else
                {
                    logger.debug("HATSDebug: the local endpoint state is null, all the states are: {}", 
                                 Gossiper.instance.endpointStateMap.get(FBUtilities.getBroadcastAddressAndPort()));
                }
                LocalStates states = new LocalStates(StorageService.instance.readCounterOfEachReplica.getCompletedRequestsOfEachReplica(), 
                                                     linearLatency, version);
                
                logger.debug("HATSDebug: foreground load {}, local read latency: {}, local read count: {}, local write latency: {}, local write count: {}, Local states: {}", 
                             StorageService.instance.totalReadCntOfEachReplica, 
                             StorageService.instance.readLatencyCalculator.getWindowMean(),
                             StorageService.instance.readLatencyCalculator.getCount(), 
                             StorageService.instance.writeLatencyCalculator.getWindowMean(), 
                             StorageService.instance.writeLatencyCalculator.getCount(),
                             states.toString());
                
                Gossiper.instance.addLocalApplicationState(ApplicationState.FOREGROUND_LOAD,
                                                           StorageService.instance.valueFactory.foregroundLoad(states));
            }
        };
        ScheduledExecutors.scheduledTasks.scheduleWithFixedDelay(runnable, 2, DatabaseDescriptor.getStateUpdateInterval(), TimeUnit.SECONDS);
    }
}

