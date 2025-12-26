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

package org.apache.cassandra.horse.net;

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

public class StatesGatheringSignal 
{

    private static final Logger logger = LoggerFactory.getLogger(StatesGatheringSignal.class);
    public static final Serializer serializer = new Serializer();

    public final boolean leaderIsSeed;

    public StatesGatheringSignal(boolean leaderIsSeed)
    {
        this.leaderIsSeed = leaderIsSeed;
    }

    public void sendStatesGatheringSignal(InetAddressAndPort followers)
    {
        Message<StatesGatheringSignal> message = Message.outWithFlag(Verb.STATE_GATHERING_SIGNAL_REQ, this, MessageFlag.CALL_BACK_ON_FAILURE);
        MessagingService.instance().send(message, followers);
    }


    public static final class Serializer implements IVersionedSerializer<StatesGatheringSignal> 
    {

        @Override
        public void serialize(StatesGatheringSignal t, DataOutputPlus out, int version) throws IOException 
        {
            out.writeBoolean(t.leaderIsSeed);
        }

        @Override
        public StatesGatheringSignal deserialize(DataInputPlus in, int version) throws IOException 
        {
            boolean leaderIsSeed = in.readBoolean();
            return new StatesGatheringSignal(leaderIsSeed);
        }

        @Override
        public long serializedSize(StatesGatheringSignal t, int version) 
        {
            long size = sizeof(t.leaderIsSeed);
            return size;
        }

    }
}
