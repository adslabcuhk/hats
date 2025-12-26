#!/bin/bash
. /etc/profile

recordcount=$1
operationcount=$2
key_length=$3
field_length=$4
threads=$5
workload=$6
requestDistribution=$7
PathToClient=$8
coordinator=$9
shift 9
targetScheme=$1
enableHats=$2
hostName=$3
readConsistency=$4

cd ${PathToClient} || exit

echo "Running YCSB with scheme: $targetScheme"

# hostName=$(hostname)

initial_workload=$workload

if [ "$workload" == "workloads/multiple" ]; then
    if [[ $hostName == "proj18" ]]; then
        workload="workloads/workloada"
    elif [[ $hostName == "proj19" ]]; then
        workload="workloads/workloadc"
    fi
elif [ "$workload" == "workloads/motivation" ]; then
    if [[ $hostName == "proj18" ]]; then
        workload="workloads/workloadUpdate"
    elif [[ $hostName == "proj19" ]]; then
        workload="workloads/workloadc"
    fi
fi

keyspace="ycsb"
if [ "$targetScheme" == "c3" ] || [ "$targetScheme" == "hats" ] || [ "$targetScheme" == "mlsm" ]; then
    sed -i "s/table=.*$/table=usertable0/" ${workload}
elif [ "$targetScheme" == "cassandra-5.0" ] || [ "$targetScheme" == "depart" ] || [ "$targetScheme" == "cassandra-3.11.4" ] || [ "$targetScheme" == "depart-5.0" ]; then
    sed -i "s/table=.*$/table=usertable/" ${workload}
else
    echo "Unknow targetScheme $targetScheme"
fi

# firstCoordinator=$(echo $coordinator | cut -d ',' -f1)
# bin/cqlsh "$firstCoordinator" -e "consistency $consistency;"


sed -i "s/recordcount=.*$/recordcount=${recordcount}/" ${workload}
sed -i "s/operationcount=.*$/operationcount=${operationcount}/" ${workload}
sed -i "s/keylength=.*$/keylength=${key_length}/" ${workload}
sed -i "s/\<fieldlength=.*/fieldlength=${field_length}/" $workload
sed -i "s/requestdistribution=.*$/requestdistribution=${requestDistribution}/" ${workload}

mkdir -p logs
file_name="Run-$(date +%s)-${hostName}-${operationcount}-${field_length}-${threads}-${requestDistribution}"



if [[ "$initial_workload" == "workloads/motivation" ]]; then
    # if [[ $hostName == "proj18" ]]; then
    #     sleep 600
    #     bin/ycsb run cassandra-cql -p maxexecutiontime=1200 -p hosts=${coordinator} -p cassandra.readconsistencylevel=$readConsistency -p cassandra.keyspace=${keyspace} -p cassandra.tracing="false"  -p enable.hats="${enableHats}" -threads $threads -s -P ${workload} > logs/${file_name}.log 2>&1
    # elif [[ $hostName == "proj19" ]]; then
    #     bin/ycsb run cassandra-cql -p maxexecutiontime=1800 -p hosts=${coordinator} -p cassandra.readconsistencylevel=$readConsistency -p cassandra.keyspace=${keyspace} -p cassandra.tracing="false"  -p enable.hats="${enableHats}" -threads $threads -s -P ${workload} > logs/${file_name}.log 2>&1
    # fi
    if [[ $hostName == "proj18" ]]; then
        sleep 1200
        bin/ycsb run cassandra-cql -p maxexecutiontime=1200 -p hosts=${coordinator} -p cassandra.readconsistencylevel=$readConsistency -p cassandra.keyspace=${keyspace} -p cassandra.tracing="false"  -p enable.hats="${enableHats}" -threads $threads -s -P ${workload} > logs/${file_name}.log 2>&1
    elif [[ $hostName == "proj19" ]]; then
        bin/ycsb run cassandra-cql -p maxexecutiontime=1200 -p hosts=${coordinator} -p cassandra.readconsistencylevel=$readConsistency -p cassandra.keyspace=${keyspace} -p cassandra.tracing="false"  -p enable.hats="${enableHats}" -threads $threads -s -P ${workload} > logs/${file_name}.log 2>&1
    fi
else
    echo "Running the workload ${workload}"
    bin/ycsb run cassandra-cql -p hosts=${coordinator} -p cassandra.readconsistencylevel=$readConsistency -p cassandra.keyspace=${keyspace} -p cassandra.tracing="false" -p enable.hats="${enableHats}" -threads $threads -s -P ${workload} > logs/${file_name}.log 2>&1
    # bin/ycsb run cassandra-cql -p hosts=${coordinator} -p cassandra.readconsistencylevel=$readConsistency -p cassandra.keyspace=${keyspace} -p cassandra.tracing="false" -p enable.hats="${enableHats}" -threads $threads -s -P ${workload} > logs/${file_name}.log 2>&1
fi

