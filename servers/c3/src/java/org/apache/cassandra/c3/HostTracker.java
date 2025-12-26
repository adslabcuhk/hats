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

package org.apache.cassandra.c3;

import java.net.InetAddress;
import java.nio.ByteBuffer;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import akka.actor.ActorRef;
import akka.actor.ActorSystem;
import akka.actor.Props;
import com.typesafe.config.Config;
import com.typesafe.config.ConfigFactory;

import org.apache.cassandra.locator.EndpointsForToken;
import org.apache.cassandra.net.Message;
import org.apache.cassandra.net.ParamType;
import org.apache.cassandra.utils.FBUtilities;

public class HostTracker
{

    private static final Logger logger = LoggerFactory.getLogger(HostTracker.class);
    private final Config config = ConfigFactory.parseString("dispatcher {\n" +
                                                            "  type = Dispatcher\n" +
                                                            "  executor = \"fork-join-executor\"\n" +
                                                            "  fork-join-executor {\n" +
                                                            "    parallelism-min = 2\n" +
                                                            "    parallelism-factor = 6.0\n" +
                                                            "    parallelism-max = 64\n" +
                                                            "  }\n" +
                                                            "  throughput = 10\n" +
                                                            "}\n");

    private final ActorSystem actorSystem = ActorSystem.create("C3", config);
    private final ConcurrentHashMap<InetAddress, ActorRef> actors = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<InetAddress, AtomicInteger> pendingRequests = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<InetAddress, RateController> rateControllers = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<InetAddress, ScoreTracker> scoreTrackers = new ConcurrentHashMap<>();

    public ActorRef getActor(EndpointsForToken  endpoints)
    {
        final InetAddress endpoint = endpoints.get(0).endpoint().getAddress();
        ActorRef actor = actors.get(endpoint);
        if (actor == null)
        {
            synchronized (this)
            {
                if (!actors.containsKey(endpoint))
                {
                    actor = actorSystem.actorOf(Props.create(ReplicaGroupActor.class).withDispatcher("dispatcher"), endpoint.getHostName());
                    actors.putIfAbsent(endpoint, actor);
                    logger.info("Creating actor for: " + endpoints);
                }
            }
            return actors.get(endpoint);
        }
        return actor;
    }

    public RateController getRateController(InetAddress endpoint) {
        return rateControllers.get(endpoint);
    }

    public ScoreTracker getScoreTracker(InetAddress endpoint) {
        if (!scoreTrackers.containsKey(endpoint)) {
            scoreTrackers.putIfAbsent(endpoint, new ScoreTracker());
        }
        return scoreTrackers.get(endpoint);
    }

    public boolean containsKey(InetAddress key) {
        return pendingRequests.containsKey(key);
    }

    public AtomicInteger put(InetAddress key, AtomicInteger value) {
        return pendingRequests.put(key, value);
    }

    public AtomicInteger get(InetAddress key) {
        return pendingRequests.get(key);
    }

    public double sendingRateTryAcquire(InetAddress endpoint)
    {
        RateController rateController = rateControllers.get(endpoint);

        if (rateController == null)
        {
            rateControllers.putIfAbsent(endpoint, new RateController());
            rateController = rateControllers.get(endpoint);
        }

        assert (rateController != null);
        return rateController.tryAcquire();
    }

    public void receiveRateTick(InetAddress endpoint)
    {
        RateController rateController = rateControllers.get(endpoint);

        if (rateController == null)
        {
            rateControllers.putIfAbsent(endpoint, new RateController());
            rateController = rateControllers.get(endpoint);
        }

        assert (rateController != null);
        rateController.receiveRateTrackerTick();
    }

    public double getScore(InetAddress endpoint) {
        RateController rateController = rateControllers.get(endpoint);
        ScoreTracker scoreTracker = scoreTrackers.get(endpoint);

        if (rateController == null) {
            rateControllers.putIfAbsent(endpoint, new RateController());
            rateController = rateControllers.get(endpoint);
        }

        if (scoreTracker == null) {
            scoreTrackers.putIfAbsent(endpoint, new ScoreTracker());
            scoreTracker = scoreTrackers.get(endpoint);
        }

        assert(rateController != null);
        assert(scoreTracker != null);

        return scoreTracker.getScore(pendingRequests, endpoint);
    }

    public AtomicInteger getPendingRequestsCounter(final InetAddress endpoint)
    {
        AtomicInteger counter = pendingRequests.get(endpoint);
        if (counter == null)
        {
            pendingRequests.put(endpoint, new AtomicInteger(0));
            counter = pendingRequests.get(endpoint);
        }

        return counter;
    }

    public void updateMetrics(Message message, long latency) {
        receiveRateTick(message.from().getAddress());
        final RateController rateController = getRateController(message.from().getAddress());
        assert (rateController != null);
        rateController.updateCubicSendingRate();
        int count = 0;
        if(pendingRequests.get(message.from().getAddress())!=null)
        {
            count = pendingRequests.get(message.from().getAddress()).decrementAndGet();
        }
        // else
        // {
        //     logger.info("HATSInfo: PendingJob count is null for Endpoint: {}", message.from().getAddress());
        // }
        logger.trace("Decrementing pendingJob count Endpoint: {}, Count: {} ", message.from().getAddress(), count);

        // int queueSize = ByteBuffer.wrap((byte[]) message.header.params().get(ParamType.QUEUE_SIZE)).getInt();
        // double serviceTimeInMillis = ByteBuffer.wrap((byte[]) message.header.params().get(ParamType.SERVICE_TIME_IN_NANO)).getLong() / 1000000.0;

        int queueSize = (int) message.header.params().get(ParamType.QUEUE_SIZE);
        long serviceTime = (long) message.header.params().get(ParamType.SERVICE_TIME_IN_NANO);
        double serviceTimeInMillis = serviceTime / 1000000.0;

        double latencyInMillis = latency / 1000000.0;
        // logger.info("HATSInfo: QueueSize: {}, ServiceTime: {}, Latency: {}", queueSize, serviceTimeInMillis, latencyInMillis);
        // assert serviceTimeInMillis < latencyInMillis;
        ScoreTracker scoreTracker = getScoreTracker(message.from().getAddress());
        scoreTracker.updateNodeScore(queueSize, serviceTimeInMillis, latencyInMillis);
    }

    // Required for handling coordinator local reads correctly
    public void updateMetricsLocal(int queueSize, long serviceTime) {
        final InetAddress from = FBUtilities.getJustBroadcastAddress();
        logger.trace("Local pendingJob count Endpoint: {}, Count: {} ", from, queueSize);

        double serviceTimeInMillis = serviceTime / 1000000.0;
        double latencyInMillis = serviceTimeInMillis;

        ScoreTracker scoreTracker = getScoreTracker(from);
        scoreTracker.updateNodeScore(queueSize, serviceTimeInMillis, latencyInMillis);
    }

}
