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

package org.apache.cassandra.horse;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;
import java.net.InetAddress;
import java.util.Set;

import org.apache.cassandra.gms.Gossiper;
import org.apache.cassandra.horse.states.GlobalStates;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.commons.io.FileUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class HorseUtils {

    private static final Logger logger = LoggerFactory.getLogger(HorseUtils.class);
    private static final String raftLogPath = System.getProperty("user.dir") + "/log/raft.log";

    public enum AKLogLevels {
        TRACE, 
        DEBUG, 
        INFO, 
        WARN, 
        ERROR
    }

    public static String getRaftLogPath()
    {
        return raftLogPath;
    }

    public static void printStackTace(AKLogLevels logLevel, String msg) 
    {
        if (logLevel.equals(AKLogLevels.DEBUG))
            logger.debug("stack trace {}", new Exception(msg));
        if (logLevel.equals(AKLogLevels.ERROR))
            logger.error("stack trace {}", new Exception(msg));
        if (logLevel.equals(AKLogLevels.INFO))
            logger.info("stack trace {}", new Exception(msg));
    }

    public static String InetAddressAndPortSetToString(Set<InetAddressAndPort> from, int port, Set<InetAddressAndPort> liveSeeds)
    {
        String to = "";
        
        for (int i = 0; i < from.size(); i++)
        {
            InetAddressAndPort ip = (InetAddressAndPort) from.toArray()[i];
            if(liveSeeds.contains(ip))
                to += ip.getHostName() + ":" + port + "::" + 1000000000;
            else
                to += ip.getHostName() + ":" + port + "::" + 100;
            if (i < from.size() - 1)
                to += ",";
        }
        return to;
        // return from.stream().map(ip -> ip.getHostName() + ":" + port + "::" + priority).collect(Collectors.joining(","));
    }

    public static void forceDelete(File path) {
        try {
            logger.debug("HATSDebug: Deleting file {}", path);
            FileUtils.forceDelete(path);
        } catch (final IOException e) {
            logger.error("Fail to delete file {}.", path);
        }
    }

    public static class ByteObjectConversion {
        public static byte[] objectToByteArray(Serializable obj) throws IOException {
            logger.debug("HORSE-Debug: start to transform");
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            ObjectOutputStream oos = new ObjectOutputStream(bos);
            oos.writeObject(obj);
            oos.flush();
            oos.close();
            bos.close();
            return bos.toByteArray();
        }

        public static Object byteArrayToObject(byte[] bytes) throws Exception {
            ByteArrayInputStream bis = new ByteArrayInputStream(bytes);
            ObjectInputStream ois = new ObjectInputStream(bis);
            Object obj = ois.readObject();
            bis.close();
            ois.close();
            return obj;
        }
    }


    public static int getReplicaIndexFromGossipInfo(int nodeIndex, InetAddress replicationGroup)
    {
        int replicaIndex = Gossiper.getAllHosts().indexOf(InetAddressAndPort.getByAddress(replicationGroup));
        if (replicaIndex == -1)
        {
            throw new IllegalStateException("Host not found in Gossiper");
        }

        int distance = Math.abs(nodeIndex - replicaIndex);

        if(distance >= 3)
        {
            return Gossiper.getAllHosts().size() - replicaIndex;
        }
        else
        {
            return distance;
        }
    }

    public static int getReplicaIndexForRGInEachNode(int rgIndex, int curNodeIndex)
    {
        int replicaIndex = curNodeIndex - rgIndex;
        if(replicaIndex < 0)
            replicaIndex = GlobalStates.globalStates.nodeCount + curNodeIndex - rgIndex;
        return replicaIndex;
    }

}
