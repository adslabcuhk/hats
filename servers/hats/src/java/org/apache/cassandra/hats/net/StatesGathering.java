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
import java.io.Serializable;
import java.net.InetAddress;
import java.util.Map;

import org.apache.cassandra.net.Message;
import org.apache.cassandra.net.MessageFlag;
import org.apache.cassandra.net.MessagingService;
import org.apache.cassandra.net.Verb;
import org.apache.cassandra.hats.HatsUtils.ByteObjectConversion;
import org.apache.cassandra.hats.states.LocalStates;
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

public class StatesGathering 
{

    private static final Logger logger = LoggerFactory.getLogger(StatesGathering.class);
    public static final Serializer serializer = new Serializer();

    public final byte[] gatheredStatesInBytes;
    private final int gatheredStatesInBytesSize;
    // Map<InetAddress, LocalStates> states
    public StatesGathering(byte[] gatheredStatesInBytes)
    {
        this.gatheredStatesInBytes = gatheredStatesInBytes;
        this.gatheredStatesInBytesSize = gatheredStatesInBytes.length;
    }

    public static void sendGatheredStates(InetAddressAndPort leader, Map<InetAddress, LocalStates> gatheredStates)
    {
        byte[] gatheredStatesInBytes = null;
                
        try {
            gatheredStatesInBytes = ByteObjectConversion.objectToByteArray((Serializable) gatheredStates);
            StatesGathering states = new StatesGathering(gatheredStatesInBytes);
            Message<StatesGathering> message = Message.outWithFlag(Verb.STATE_GATHERING_REQ, states, MessageFlag.CALL_BACK_ON_FAILURE);
            MessagingService.instance().send(message, leader);
            logger.info("hatsINFO: Sent states to leader {}, state size is {}.", leader, gatheredStatesInBytes.length);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }


    public static final class Serializer implements IVersionedSerializer<StatesGathering> 
    {

        @Override
        public void serialize(StatesGathering t, DataOutputPlus out, int version) throws IOException 
        {
            out.writeInt(t.gatheredStatesInBytesSize);
            out.write(t.gatheredStatesInBytes);
        }

        @Override
        public StatesGathering deserialize(DataInputPlus in, int version) throws IOException 
        {
            int gatheredStatesInBytesSize = in.readInt();
            byte[] gatheredStatesInBytes = new byte[gatheredStatesInBytesSize];
            in.readFully(gatheredStatesInBytes);
            return new StatesGathering(gatheredStatesInBytes);
        }

        @Override
        public long serializedSize(StatesGathering t, int version) 
        {
            long size = t.gatheredStatesInBytesSize + sizeof(t.gatheredStatesInBytesSize);
            return size;
        }

    }
}
