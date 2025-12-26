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

import org.apache.cassandra.hats.HatsUtils.ByteObjectConversion;
import org.apache.cassandra.hats.states.GlobalStates;
import org.apache.cassandra.hats.states.LocalStates;
import org.apache.cassandra.hats.states.GlobalStates.LoadBalancingStrategy;
import org.apache.cassandra.net.IVerbHandler;
import org.apache.cassandra.net.Message;
import org.apache.cassandra.service.StorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


/**
 * @author anonymous@gmail.com
 */

public class SendNewStatesVerbHandler implements IVerbHandler<SendNewStates>{

    public static final SendNewStatesVerbHandler instance = new SendNewStatesVerbHandler();
    private static final Logger logger = LoggerFactory.getLogger(SendNewStatesVerbHandler.class);
    @Override
    public void doVerb(Message<SendNewStates> message) throws IOException {
        try {
            logger.info("HATSInfo: Received placement policy from the leader: {}", message.from());
            GlobalStates.expectedStates = (LoadBalancingStrategy) ByteObjectConversion.byteArrayToObject(message.payload.placementPolicyInBytes);
            logger.info("HATSInfo: Received expected states: {}, the term id is {}, version number is {}, expected distribution is {}", GlobalStates.expectedStates, GlobalStates.expectedStates.termId, GlobalStates.expectedStates.version, GlobalStates.expectedStates.expectedRequestDistribution);
            // Get the local placement policy
            GlobalStates.updatePolicyForCurrentNode();

            logger.info("HATSInfo: the expected request number of each node is {}, the background policy is {}", GlobalStates.expectedRequestNumberofEachNode, LocalStates.backgroundPolicy);

            // Get the placement policy for local replicas
        } catch (Exception e) {
            // TODO Auto-generated catch block
            logger.error("hatsERROR: Failed to deserialize the placement policy from the received message");
            e.printStackTrace();
        }


        // Acknowledge to the client driver
        StorageService.instance.notifyPolicy(GlobalStates.transformPolicyForClient(), GlobalStates.getGlobalCoordinatorReadLatencyFromGossipInfo());
        
    }
    
}
