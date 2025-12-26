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

. /etc/profile

# pkill -9 -f CassandraDaemon || true
func() {
    coordinator=$1
    record_count=$2
    key_length=$3
    field_length=$4
    threads=$5
    file_dir=$6
    workload=$7
    expName=$8
    replication_factor=$9
    shift 9
    mode=$1

    cd ${file_dir}
    echo "Mode is $mode, file_dir is $file_dir, coordinator is $coordinator, record_count is $record_count, key_length is $key_length, field_length is $field_length, threads is $threads, workload is $workload, expName is $expName, replication_factor is $replication_factor"
    keyspace=""
    if [ "$mode" == "mlsm" ] || [ "$mode" == "hats" ]; then
        keyspace="ycsb"
        sed -i "s/table=.*$/table=usertable0/" ${workload}
    else
        keyspace="ycsb"
        sed -i "s/table=.*$/table=usertable/" ${workload}
    fi
    


    mkdir -p logs/
    mkdir -p results/load-results/
    sed -i "s/recordcount=.*$/recordcount=${record_count}/" $workload
    sed -i "s/\<fieldlength=.*/fieldlength=${field_length}/" $workload
    # sed -i "s/requestdistribution=.*$/requestdistribution=${requestDistribution}/" $workload
    file_name="Load-$(date +%s)-${record_count}-${field_length}-${threads}-${replication_factor}"
    # nohup bin/ycsb load cassandra-cql -p hosts=$coordinator -threads $threads -s -P workloads/workload_template > logs/${file_name}.log 2>&1 &

    bin/ycsb load cassandra-cql -p hosts=$coordinator -p cassandra.keyspace=${keyspace} -threads $threads -s -P $workload > logs/${file_name}.log 2>&1
    # histogram -i results/load-results/${file_name}
}

func "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"
