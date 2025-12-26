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
import java.io.Serializable;

import org.apache.cassandra.net.Message;
import org.apache.cassandra.net.MessageFlag;
import org.apache.cassandra.net.MessagingService;
import org.apache.cassandra.net.Verb;
import org.apache.cassandra.horse.HorseUtils.ByteObjectConversion;
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

public class PolicyDistribute 
{

    private static final Logger logger = LoggerFactory.getLogger(PolicyDistribute.class);
    public static final Serializer serializer = new Serializer();

    public final byte[] placementPolicyInBytes;
    private final int placementPolicyInBytesSize;
    // Map<InetAddress, LocalStates> states
    public PolicyDistribute(byte[] placementPolicyInBytes)
    {
        this.placementPolicyInBytes = placementPolicyInBytes;
        this.placementPolicyInBytesSize = placementPolicyInBytes.length;
    }

    public static void sendPlacementPolicy(InetAddressAndPort dataNode, Double[] placementPolicy)
    {
        byte[] placementPolicyInBytes = null;
                
        try {
            placementPolicyInBytes = ByteObjectConversion.objectToByteArray((Serializable) placementPolicy);
            PolicyDistribute policy = new PolicyDistribute(placementPolicyInBytes);
            Message<PolicyDistribute> message = Message.outWithFlag(Verb.POLICY_DISTRIBUTE_REQ, policy, MessageFlag.CALL_BACK_ON_FAILURE);
            MessagingService.instance().send(message, dataNode);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }


    public static final class Serializer implements IVersionedSerializer<PolicyDistribute> 
    {

        @Override
        public void serialize(PolicyDistribute t, DataOutputPlus out, int version) throws IOException 
        {
            out.writeInt(t.placementPolicyInBytesSize);
            out.write(t.placementPolicyInBytes);
        }

        @Override
        public PolicyDistribute deserialize(DataInputPlus in, int version) throws IOException 
        {
            int placementPolicyInBytesSize = in.readInt();
            byte[] placementPolicyInBytes = new byte[placementPolicyInBytesSize];
            in.readFully(placementPolicyInBytes);
            return new PolicyDistribute(placementPolicyInBytes);
        }

        @Override
        public long serializedSize(PolicyDistribute t, int version) 
        {
            long size = t.placementPolicyInBytesSize + sizeof(t.placementPolicyInBytesSize);
            return size;
        }

    }
}
