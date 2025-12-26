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

import org.apache.cassandra.hats.states.GlobalStates;
import org.apache.cassandra.net.IVerbHandler;
import org.apache.cassandra.net.Message;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


/**
 * @author anonymous@gmail.com
 */

public class GossipStatesDigestVerbHandler implements IVerbHandler<GossipStatesDigest>{

    public static final GossipStatesDigestVerbHandler instance = new GossipStatesDigestVerbHandler();
    private static final Logger logger = LoggerFactory.getLogger(GossipStatesDigestVerbHandler.class);
    @Override
    public void doVerb(Message<GossipStatesDigest> message) throws IOException {
        GossipStatesDigest payload = message.payload;
        int termId = payload.termId;
        int version = payload.versionId;

        if(GlobalStates.expectedStates == null)
        {
            RequestNewStates.requestNewExpectedStates(message.from());
        }
        else
        {
            if(GlobalStates.expectedStates.termId > termId || (GlobalStates.expectedStates.termId == termId && GlobalStates.expectedStates.version > version))
            {
                // respond with the placement policy. GossipStatesAck  
                SendNewStates.sendNewExpectedStates(message.from(), GlobalStates.expectedStates);
            }
            else if(GlobalStates.expectedStates.termId < termId || (GlobalStates.expectedStates.termId == termId && GlobalStates.expectedStates.version < version))
            {
                // request the placement policy. GossipStatesAck2
                RequestNewStates.requestNewExpectedStates(message.from());
            }
            else
            {
                // do nothing
            }
        }
    }
    
}
