/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.cassandra.hats.leaderelection.election;


import java.io.File;
import java.util.Set;

import org.apache.cassandra.hats.HatsUtils;
import org.apache.cassandra.hats.Scheduler;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.alipay.sofa.jraft.entity.PeerId;

/**
 *
 * @author jiachun.fjc
 */
public class ElectionBootstrap {

    // Start elections by 3 instance. Note that if multiple instances are started on the same machine,
    // the first parameter `dataPath` should not be the same.

    private static final Logger logger = LoggerFactory.getLogger(ElectionBootstrap.class);
    private static ElectionNode node;
    private static int leaderTerm = 0;
    public static void initElection(String dataPath, String groupId, String serverIdStr, String initialConfStr)
    {
        logger.info("HATSInfo: Starting election with dataPath: {}, groupId: {}, serverIdStr: {}, initialConfStr: {}",
                    dataPath, groupId, serverIdStr, initialConfStr);
        File dataPathFile = new File(dataPath);
        if(dataPathFile.exists())
        {
            HatsUtils.forceDelete(dataPathFile);
        }
        node = new ElectionNode();
        final ElectionNodeOptions electionOpts = new ElectionNodeOptions();
        electionOpts.setDataPath(dataPath);
        electionOpts.setGroupId(groupId);
        electionOpts.setServerAddress(serverIdStr);
        electionOpts.setInitialServerAddressList(initialConfStr);

        node.addLeaderStateListener(new LeaderStateListener() {

            @Override
            public void onLeaderStart(long leaderTerm) {
                PeerId serverId = node.getNode().getLeaderId();
                String ip = serverId.getIp();
                int port = serverId.getPort();
                leaderTerm = (int) leaderTerm;
                Scheduler.version.set(0);
                logger.debug("HATSDebug: [ElectionBootstrap] Leader's ip is: {}, port: {}", ip, port);
                logger.debug("HATSDebug: [ElectionBootstrap] Leader start on term: {}", leaderTerm);
            }

            @Override
            public void onLeaderStop(long leaderTerm) {
                logger.debug("HATSDebug: [ElectionBootstrap] Leader stop on term: {}", leaderTerm);
            }
        });
        node.init(electionOpts);
    }

    public static Boolean isLeader()
    {
        if (node != null)
        {
            return node.isLeader();
        }
        
        logger.debug("HATSDebug: Election node is not initialized");
        return false;
    }

    public static Boolean isStarted()
    {
        if (node != null)
        {
            return node.isStarted();
        }
        
        logger.debug("HATSDebug: Election node is not initialized");
        return false;
    }

    public static String getLeader()
    {
        PeerId serverId = node.getNode().getLeaderId();
        String ip = serverId.getIp();
        return ip;
    }

    public static int getLeaderTerm()
    {
        return leaderTerm;
    }

    public static void shutdownElection(Set<InetAddressAndPort> liveSeeds)
    {
        if (node != null && node.isStarted())
        {
            node.shutdown();
        }
        else
        {
            logger.debug("HATSDebug: Election node is not initialized");
        }
    }


    public static void main(final String[] args) {
        if (args.length < 4) {
            System.out
                .println("Usage : java com.alipay.sofa.jraft.example.election.ElectionBootstrap {dataPath} {groupId} {serverId} {initConf}");
            System.out
                .println("Example: java com.alipay.sofa.jraft.example.election.ElectionBootstrap /tmp/server1 election_test 127.0.0.1:8081 127.0.0.1:8081,127.0.0.1:8082,127.0.0.1:8083");
            System.exit(1);
        }
        final String dataPath = args[0];
        final String groupId = args[1];
        final String serverIdStr = args[2];
        final String initialConfStr = args[3];

        initElection(dataPath, groupId, serverIdStr, initialConfStr);
    }
}
