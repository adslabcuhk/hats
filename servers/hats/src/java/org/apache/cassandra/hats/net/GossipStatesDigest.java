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

import org.apache.cassandra.net.Message;
import org.apache.cassandra.net.MessageFlag;
import org.apache.cassandra.net.MessagingService;
import org.apache.cassandra.net.Verb;
import org.apache.cassandra.io.IVersionedSerializer;
import org.apache.cassandra.io.util.DataInputPlus;
import org.apache.cassandra.io.util.DataOutputPlus;
import org.apache.cassandra.locator.InetAddressAndPort;

import static org.apache.cassandra.db.TypeSizes.sizeof;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


/**
 * @author anonymous@gmail.com
 */

public class GossipStatesDigest 
{

    private static final Logger logger = LoggerFactory.getLogger(GossipStatesDigest.class);
    public static final Serializer serializer = new Serializer();

    public final int termId;
    public final int versionId;
    // Map<InetAddress, LocalStates> states
    public GossipStatesDigest(int termId, int version)
    {
        this.termId = termId;
        this.versionId = version;
    }

    public static void sendStatesDisgestMessage(InetAddressAndPort target, int termId, int version)
    {
        GossipStatesDigest policy = new GossipStatesDigest(termId, version);
        Message<GossipStatesDigest> message = Message.outWithFlag(Verb.GOSSIP_STATES_DIGEST_REQ, policy, MessageFlag.CALL_BACK_ON_FAILURE);
        MessagingService.instance().send(message, target);
    }


    public static final class Serializer implements IVersionedSerializer<GossipStatesDigest> 
    {

        @Override
        public void serialize(GossipStatesDigest t, DataOutputPlus out, int version) throws IOException 
        {
            out.writeInt(t.termId);
            out.writeInt(t.versionId);
        }

        @Override
        public GossipStatesDigest deserialize(DataInputPlus in, int version) throws IOException 
        {
            int termId = in.readInt();
            int versionId = in.readInt();
            return new GossipStatesDigest(termId, versionId);
        }

        @Override
        public long serializedSize(GossipStatesDigest t, int version) 
        {
            long size = sizeof(t.termId) + sizeof(t.versionId);
            return size;
        }

    }
}
