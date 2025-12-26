/*
 *      Copyright (C) 2012-2015 DataStax Inc.
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */
package com.datastax.driver.core;


/**
 * Options of the Hats
 */
public class HatsOptions {


    public static final boolean ENABLE_HATS = false;
    private volatile boolean enableHats = ENABLE_HATS;

    public static final boolean SHUFFLE_REPLICAS = true;
    private volatile boolean shuffleReplicas = SHUFFLE_REPLICAS;


    /**
     * Creates a new {@code ProtocolOptions} instance using the {@code DEFAULT_PORT}
     * (and without SSL).
     */
    public HatsOptions() {
    }

    /**
     * Returns whether the hats is enabled.
     *
     * @return whether the hats is enabled.
     */
    public boolean isHatsEnabled() {
        return enableHats;
    }

    /**
     * Setup the hats.
     *
     * @param enableHats whether to enable the hats.
     */
    public HatsOptions setHats(boolean enableHats) {
        this.enableHats = enableHats;
        return this;
    }

    /**
     * Returns whether the replicas are shuffled.
     *
     * @return whether the replicas are shuffled.
     */
    public boolean isShuffleReplicas() {
        return shuffleReplicas;
    }

    /**
     * Setup the shuffle replicas.
     *
     * @param shuffleReplicas whether to shuffle the replicas.
     */

    public HatsOptions setShuffleReplicas(boolean shuffleReplicas) {
        this.shuffleReplicas = shuffleReplicas;
        return this;
    }
}
