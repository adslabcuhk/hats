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
package org.apache.cassandra.tools.nodetool;

import static org.apache.commons.lang3.StringUtils.EMPTY;

import io.airlift.airline.Command;
import io.airlift.airline.Option;

import org.apache.cassandra.tools.NodeProbe;
import org.apache.cassandra.tools.NodeTool.NodeToolCmd;

@Command(name = "sethats", description = "Setup the parameters for Hats")
public class SetHats extends NodeToolCmd
{

    @Option(title = "enable_hats", name = {"-e", "--enable"}, description = "Use --enable to decide whether enable the hats or not")
    private String enableHats = EMPTY;

    // step_size double
    @Option(title = "step_size", name = {"-ss", "--step-size"}, description = "Use -ss to specify the step size for the hats")
    private String step_size = EMPTY;

    // offload_threshold
    @Option(title = "offload_threshold", name = {"-ot", "--offload-threshold"}, description = "Use -ot to specify the offload threshold for the hats")
    private String offload_threshold = EMPTY;

    // recovery_threshold
    @Option(title = "recovery_threshold", name = {"-rt", "--recovery-threshold"}, description = "Use -rt to specify the recovery threshold for the hats")
    private String recovery_threshold = EMPTY;

    @Override
    public void execute(NodeProbe probe)
    {
        try
        {
            probe.setHats(enableHats, step_size, offload_threshold, recovery_threshold);
        }
        catch (IllegalArgumentException e)
        {
            String message = e.getMessage() != null ? e.getMessage() : "invalid hats parameters";
            probe.output().out.println("Unable to set hats parameters: " + message);
            System.exit(1);
        }
    }
}
