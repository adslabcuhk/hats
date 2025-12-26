#!/bin/bash
# . /etc/profile
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# source "${SCRIPT_DIR}/../common.sh"
function restartNode {
    configureFilePath=$1
    sourceDataDir=$2
    projectBaseDir=$3
    memtableSize=$4
    motivation=$5
    rebuild=$6
    useDirectIO=$7
    branch=$8
    shift 8
    schedulingInitialDelay=$1
    schedulingInterval=$2
    statesUpdateInterval=$3
    readSensitivity=$4
    enableHats=$5
    throttleDataRate=$6
    enableFineSchedule=$7
    enableBackgroundSchedule=$8

    echo "Restart the node with configure file ${configureFilePath}, source data dir ${sourceDataDir}, project base dir ${projectBaseDir}, memtable size ${memtableSize}, motivation ${motivation}, the pass word is ${passWd}, rebuild is ${rebuild}, use direct io is ${useDirectIO}, branch is ${branch}, scheduling initial delay is ${schedulingInitialDelay}, scheduling interval is ${schedulingInterval}, states update interval is ${statesUpdateInterval}, read sensitivity is ${readSensitivity}"

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
    

    rm -rf data
    # if [ "${fromBackup}" == "true" ]; then
    echo "Copy DB data back from ${sourceDataDir} to ${projectBaseDir}/data"
    if [ ! -d "${sourceDataDir}" ]; then
        echo "The backup data in ${sourceDataDir} does not exist"
        exit
    fi
    cp -r ${sourceDataDir} data
    chmod -R 775 data
    echo "$passWd" | sudo -S sh -c "echo 1 > /proc/sys/vm/drop_caches"
    # else
    #     mkdir -p data
    # fi


    rm -rf logs metrics
    mkdir -p logs metrics

    # nohup bin/cassandra >logs/debug.log 2>&1 &

}

restartNode "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" "${14}" "${15}" "${16}"