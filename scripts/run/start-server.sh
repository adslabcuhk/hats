# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


pkill -9 -f CassandraDaemon || true

func() {


    cd $code_base
    # git pull
    # git checkout ${branch_name}
    # git pull origin ${branch_name}


    rm -rf data logs metrics
    mkdir -p data
    mkdir -p logs
    mkdir -p metrics

    # if [ "$rebuild" == "true" ]; then
    #     ant clean && ant -Duse.jdk11=true
    # fi
    
    
    # sed -i "s/seeds:.*$/seeds: \"${seeds}\"/" conf/cassandra.yaml
    sed -i "s/memtable_heap_space:.*$/memtable_heap_space: ${memtable_heap_space}/" conf/cassandra.yaml

    sed -i "s/internode_max_message_size:.*$/internode_max_message_size: ${internode_max_message_size}/" conf/cassandra.yaml
    sed -i "s/internode_application_send_queue_capacity:.*$/internode_application_send_queue_capacity: ${internode_application_send_queue_capacity}/" conf/cassandra.yaml
    sed -i "s/internode_application_send_queue_reserve_endpoint_capacity:.*$/internode_application_send_queue_reserve_endpoint_capacity: ${internode_application_send_queue_reserve_endpoint_capacity}/" conf/cassandra.yaml
    sed -i "s/internode_application_send_queue_reserve_global_capacity:.*$/internode_application_send_queue_reserve_global_capacity: ${internode_application_send_queue_reserve_global_capacity}/" conf/cassandra.yaml
    sed -i "s/internode_application_receive_queue_capacity:.*$/internode_application_receive_queue_capacity: ${internode_application_receive_queue_capacity}/" conf/cassandra.yaml
    sed -i "s/internode_application_receive_queue_reserve_endpoint_capacity:.*$/internode_application_receive_queue_reserve_endpoint_capacity: ${internode_application_receive_queue_reserve_endpoint_capacity}/" conf/cassandra.yaml
    sed -i "s/internode_application_receive_queue_reserve_global_capacity:.*$/internode_application_receive_queue_reserve_global_capacity: ${internode_application_receive_queue_reserve_global_capacity}/" conf/cassandra.yaml

    # nohup bin/cassandra &> logs/debug.log &
    nohup bin/cassandra > logs/debug.log 2>&1 &

}

func #"$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "$10" "$11" "$12" "$13" "$14" "$15"