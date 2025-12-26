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

import akka.actor.UntypedActorWithStash;
import akka.japi.Procedure;

import org.apache.cassandra.service.StorageService;
import org.apache.cassandra.service.reads.AbstractReadExecutor;
import scala.concurrent.duration.Duration;

import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class ReplicaGroupActor extends UntypedActorWithStash
{

    private static final Logger logger = LoggerFactory.getLogger(ReplicaGroupActor.class);

    private final Procedure<Object> WAITING_STATE = new Procedure<Object>()
    {
        @Override
        public void apply(Object msg) throws Exception
        {
            if (msg instanceof ReplicaGroupActorCommand)
            {
                switch ((ReplicaGroupActorCommand) msg)
                {
                    case UNBLOCK:
                        getContext().unbecome();
                        unstashAll();
                        break;
                    default:
                        throw new AssertionError("Received invalid command " + msg);
                }
            }
            else
            {
                stash();
            }
        }
    };

    @Override
    public void onReceive(Object msg)
    {
        if (msg instanceof AbstractReadExecutor)
        {
            logger.debug("C3-Debug: Received read request and push it to the replica selection scheduler.");
            long durationToWait = (long) ((AbstractReadExecutor) msg).pushRead();
            StorageService.instance.readWaitTime += durationToWait;

            if (durationToWait > 0)
            {
                stash();
                switchToWaiting(durationToWait);
            }
        }
    }

    private void switchToWaiting(final long durationToWait)
    {
        System.out.println("Switching to waiting " + durationToWait);
        getContext().become(WAITING_STATE, false);
        getContext().system().scheduler().scheduleOnce(
                                                      Duration.create(durationToWait, TimeUnit.NANOSECONDS),
                                                      getSelf(),
                                                      ReplicaGroupActorCommand.UNBLOCK,
                                                      getContext().system().dispatcher(),
                                                      null);
    }

    enum ReplicaGroupActorCommand
    {
        BLOCK,
        UNBLOCK,
    }

    
}
