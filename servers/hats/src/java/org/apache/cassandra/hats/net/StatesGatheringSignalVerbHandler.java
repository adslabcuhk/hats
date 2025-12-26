/**
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
package org.apache.cassandra.hats.net;

import java.io.IOException;
import java.net.InetAddress;
import java.util.HashMap;
import java.util.Map;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.gms.ApplicationState;
import org.apache.cassandra.gms.EndpointState;
import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.hats.leaderelection.election.ElectionBootstrap;
import org.apache.cassandra.hats.leaderelection.priorityelection.PriorityElectionBootstrap;
import org.apache.cassandra.hats.states.LocalStates;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.net.IVerbHandler;
import org.apache.cassandra.net.Message;
import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.utils.FBUtilities;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;



/**
 * @author anonymous@gmail.com
 */

public class StatesGatheringSignalVerbHandler implements IVerbHandler<StatesGatheringSignal>{

    public static final StatesGatheringSignalVerbHandler instance = new StatesGatheringSignalVerbHandler();
    private static final Logger logger = LoggerFactory.getLogger(StatesGatheringSignalVerbHandler.class);
    @Override
    public void doVerb(Message<StatesGatheringSignal> message) throws IOException {
        StatesGatheringSignal signal = message.payload;

        Map<InetAddress, LocalStates> gatheredStates = new HashMap<>();

        logger.info("hatsINFO: Received states gathering signal from {}.", message.from());

        String leaderHost = "";
        // Followers send the load statistic to the leader
        if(signal.leaderIsSeed)
        {
            leaderHost = ElectionBootstrap.getLeader();

            for (Map.Entry<InetAddressAndPort, EndpointState> entry : Gossiper.instance.endpointStateMap.entrySet())
            {
                if(entry.getValue().getApplicationState(ApplicationState.FOREGROUND_LOAD) == null)
                {
                    logger.info("HATSInfo: No foreground load state for {}.", entry.getKey().getAddress());
                    continue;
                }
                String localStatesStr = entry.getValue().getApplicationState(ApplicationState.FOREGROUND_LOAD).value;
                int version = entry.getValue().getApplicationState(ApplicationState.FOREGROUND_LOAD).version;
                LocalStates localStates = LocalStates.fromString(localStatesStr, version);
                if (localStates == null) {
                    continue;
                }
                gatheredStates.put(entry.getKey().getAddress(), localStates);
            }
        }
        else
        {
            leaderHost = PriorityElectionBootstrap.getLeader();
            double linearLatency = StorageService.instance.localReadLatencyCalculator.getLatencyForLocalStates();
            // double linearLatency = StorageService.instance.readLatencyCalculator.getLatencyForLocalStates();
                                //    StorageService.instance.readLatencyCalculator.getMedian() * 
                                //    DatabaseDescriptor.getReadSensitiveFactor() +
                                //    StorageService.instance.writeLatencyCalculator.getMedian() * 
                                //    (1 - DatabaseDescriptor.getReadSensitiveFactor());
            int version = Gossiper.instance.endpointStateMap.get(FBUtilities.getBroadcastAddressAndPort())
                                                            .getApplicationState(ApplicationState.FOREGROUND_LOAD)
                                                            .version;
            LocalStates localStates = new LocalStates(StorageService.instance
                                                                    .readCounterOfEachReplica
                                                                    .getCompletedRequestsOfEachReplica(), 
                                                     linearLatency, version);
            gatheredStates.put(StorageService.instance.localIP, localStates);
        }

        if(!InetAddressAndPort.getByName(leaderHost).equals(message.from()))
        {
            throw new IllegalArgumentException("Leader host is not the same as the current host");
        }

        StatesGathering.sendGatheredStates(message.from(), gatheredStates);

    }
    
}
