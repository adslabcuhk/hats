#!/bin/bash
. /etc/profile
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# source "${SCRIPT_DIR}/../common.sh"
function restartCassandra {
    configureFilePath=$1
    projectBaseDir=$2
    memtableSize=$3
    motivation=$4
    rebuild=$5
    useDirectIO=$6
    branch=$7
    schedulingInitialDelay=$8
    schedulingInterval=$9
    shift 9
    statesUpdateInterval=$1
    readSensitivity=$2
    enableHats=$3
    throttleDataRate=$4
    enableFineSchedule=$5
    enableBackgroundSchedule=$6

    echo "Restart the node with configure file ${configureFilePath}, project base dir ${projectBaseDir}, memtable size ${memtableSize}, motivation ${motivation}, enable hats ${enableHats}"

    pkill -9 -f CassandraDaemon || true



    cd "${projectBaseDir}" || exit

    # if [ "$rebuild" == "true" ]; then
    #     git checkout "${branch}"
    #     git pull origin "${branch}"
    #     ant clean && ant -Duse.jdk11=true
    # fi

    sed -i "s/memtable_heap_space:.*$/memtable_heap_space: ${memtableSize}/" conf/cassandra.yaml
    sed -i "s/motivation:.*$/motivation: "${motivation}"/" conf/cassandra.yaml
    sed -i "s/enable_direct_io_for_read_path:.*$/enable_direct_io_for_read_path: "${useDirectIO}"/" conf/cassandra.yaml
    sed -i "s/scheduling_initial_delay:.*$/scheduling_initial_delay: "${schedulingInitialDelay}"/" conf/cassandra.yaml
    sed -i "s/scheduling_interval:.*$/scheduling_interval: "${schedulingInterval}"/" conf/cassandra.yaml
    sed -i "s/state_update_interval:.*$/state_update_interval: "${statesUpdateInterval}"/" conf/cassandra.yaml
    sed -i "s/read_sensitive_factor:.*$/read_sensitive_factor: "${readSensitivity}"/" conf/cassandra.yaml

    if [ "${enableHats}" == "true" ]; then
        sed -i "s/enable_hats:.*$/enable_hats: "${enableHats}"/" conf/cassandra.yaml
        sed -i "s/throttle_data_rate:.*$/throttle_data_rate: "${throttleDataRate}"/" conf/cassandra.yaml
        sed -i "s/enable_fine_schedule:.*$/enable_fine_schedule: "${enableFineSchedule}"/" conf/cassandra.yaml
        sed -i "s/enable_background_schedule:.*$/enable_background_schedule: "${enableBackgroundSchedule}"/" conf/cassandra.yaml
    fi




    

    rm -rf logs metrics
    mkdir -p logs metrics

    # nohup bin/cassandra >logs/debug.log 2>&1 &
}

restartCassandra "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" "${14}" "${15}"
