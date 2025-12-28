#!/bin/bash
. /etc/profile
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source ${SCRIPT_DIR}/settings.sh

playbookSet=(playbook-load.yaml playbook-run.yaml playbook-flush.yaml playbook-backup.yaml playbook-startup.yaml playbook-fail.yaml playbook-recovery.yaml)
# Initialize an empty array to store tokens
tokens=()
TokenRanges=""
function getToken {
    nodeNum=$1
    # Get the output of the genToken.py script
    output=$(python3 ${SCRIPT_DIR}/genToken.py ${nodeNum} ${NumTokens})
    tokens=()
    TokenRanges=""
    # Extract tokens from the output and add them to the array
    while read -r line; do
        if [[ $line == initial_token:* ]]; then
            # Extract the token value using parameter expansion
            token=${line#initial_token: }
            echo "Get token $token"
            # Add the token to the array
            tokens+=("$token")
        fi
    done <<< "$output"

    # Construct the token ranges
    for i in "${!tokens[@]}"; do
        TokenRanges+="${tokens[i]}"
        if [ $i -ne $((${#tokens[@]} - 1)) ]; then
            TokenRanges+=","
        fi
    done
}

function initConf {

    realSeeds=$1

    if [[ $realSeeds == "true" ]]; then
        seeds=${SEEDS}
    else
        seeds=${ALL_SERVERS}
    fi

    getToken ${#ServersIP[@]}
    # # Modify the the rpc_address listen_address seeds initial_token in the cassandra.yaml
    for ((i=0; i<${#ServersIP[@]}; i++)); do
        node_ip=${ServersIP[$i]}
        node=${Servers[$i]}
        token=${tokens[$i]}
        echo "Set set the initial token of ${node} as ${token}"

        conf_dir="${SCRIPT_DIR}/conf/$SCHEME"
        

        if [[ $SCHEME == "depart" ]] || [[ $SCHEME == "cassandra-3.11.4" ]] || [[ $SCHEME == "cassandra-5.0" ]] || [[ $SCHEME == "depart-5.0" ]]; then
            sed -i "s/rpc_address:.*$/rpc_address: ${node_ip}/" ${conf_dir}/cassandra.yaml
            sed -i "s/listen_address:.*$/listen_address: ${node_ip}/" ${conf_dir}/cassandra.yaml
            sed -i "s/seeds:.*$/seeds: \"${seeds}\"/" ${conf_dir}/cassandra.yaml
            sed -i "s/initial_token:.*$/initial_token: ${token}/" ${conf_dir}/cassandra.yaml
            sed -i "s/num_tokens:.*$/num_tokens: ${NumTokens}/" ${conf_dir}/cassandra.yaml
        elif [[ $SCHEME == "hats" ]] || [[ $SCHEME == "mlsm" ]] || [[ $SCHEME == "c3" ]]; then
            sed -i "s/rpc_address:.*$/rpc_address: ${node_ip}/" ${conf_dir}/cassandra.yaml
            sed -i "s/listen_address:.*$/listen_address: ${node_ip}/" ${conf_dir}/cassandra.yaml
            sed -i "s/initial_token:.*$/initial_token: ${token}/" ${conf_dir}/cassandra.yaml
            sed -i "s/seeds:.*$/seeds: \"${seeds}\"/" ${conf_dir}/cassandra.yaml
            sed -i "s/token_ranges:.*$/token_ranges: ${TokenRanges}/" ${conf_dir}/cassandra.yaml
            sed -i "s/num_tokens:.*$/num_tokens: ${NumTokens}/" ${conf_dir}/cassandra.yaml
            sed -i "s/all_hosts:.*$/all_hosts: \"${Coordinators}\"/" ${conf_dir}/cassandra.yaml
        fi
        
        scp ${conf_dir}/cassandra.yaml ${node}:${PathToServer}/conf/cassandra.yaml
    done

    # modify the hosts.ini
    > ${SCRIPT_DIR}/playbook/hosts.ini
    echo "[cassandra_servers]" >> ${SCRIPT_DIR}/playbook/hosts.ini
    for node in "${Servers[@]}"; do
        echo "${node} ansible_host=${node}" >> ${SCRIPT_DIR}/playbook/hosts.ini
    done
    if [[ $realSeeds == "true" ]]; then
        echo "[cassandra_seeds]" >> ${SCRIPT_DIR}/playbook/hosts.ini
        for seed in "${Seeds[@]}"; do
            echo "${seed} ansible_host=${seed}" >> ${SCRIPT_DIR}/playbook/hosts.ini
        done
        echo "[cassandra_data_nodes]" >> ${SCRIPT_DIR}/playbook/hosts.ini
        for node in "${Servers[@]}"; do
            if printf '%s\n' "${Seeds[@]}" | grep -q -P "^${node}$"; then
                continue
            fi
            echo "${node} ansible_host=${node}" >> ${SCRIPT_DIR}/playbook/hosts.ini
        done
    else
        echo "[cassandra_seeds]" >> ${SCRIPT_DIR}/playbook/hosts.ini
        for node in "${Servers[@]}"; do
            echo "${node} ansible_host=${node}" >> ${SCRIPT_DIR}/playbook/hosts.ini
        done
    fi

    echo "[cassandra_clients]" >> ${SCRIPT_DIR}/playbook/hosts.ini
    for client in "${Clients[@]}"; do
        echo "${client} ansible_host=${client}" >> ${SCRIPT_DIR}/playbook/hosts.ini
    done

}


function treeSizeEstimation {
    kvNumber=$1
    keylength=$2
    fieldlength=$3
    initial_count=${SSTableSize}
    ratio=${LSMTreeFanOutRatio}
    target_count=$((kvNumber * (keylength + fieldlength) / ServerNumber / 1024 / 1024 / 4))

    current_count=$initial_count
    current_level=1

    while [ $current_count -lt $target_count ]; do
        current_count=$((current_count * ratio))
        current_level=$((current_level + 1))
    done
    treeLevels=$((current_level))
    echo ${treeLevels}
}

function dataSizeEstimation {
    kvNumber=$1
    keylength=$2
    fieldlength=$3
    rf=$4
    dataSizeOnEachNode=$(echo "scale=2; $kvNumber * ($keylength + $fieldlength) / $ServerNumber / 1024 / 1024 / 1024 * $rf" | bc)
    echo ${dataSizeOnEachNode}
}


function waitFlushCompactionTimeEstimation {
    dataSizeOnEachNode=$1
    waitTime=$(echo "scale=2; $dataSizeOnEachNode * 500" | bc)
    waitTimeCeil=$(echo "scale=0; (${waitTime} + 0.5)/1" | bc)
    echo ${waitTimeCeil}

}

function resetPlaybook {
    task=$1
    if [ -f "playbook-${task}.yaml" ]; then
        rm -rf playbook-${task}.yaml
    fi
    cp ../playbook/playbook-${task}.yaml .
    cp ../playbook/hosts.ini .
}

function flush {
    expName=$1
    targetScheme=$2
    waitTime=$3
    echo "Start for flush and wait for compaction of ${targetScheme}, waiting ${waitTime} seconds"


    # Copy playbook
    resetPlaybook "flush"
    playbook="playbook-flush.yaml"

    # Modify playbook
    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|PATH_TO_SCRIPTS|${PathToScripts}|g" ${playbook}
    sed -i "s|PATH_TO_BACKUP|${PathToBackup}|g" ${playbook}
    sed -i "s/\(seconds: \)".*"/seconds: ${waitTime}/" ${playbook}
    if [ $targetScheme == "depart" ]|| [ $targetScheme == "cassandra-3.11.4" ]; then
        sed -i 's|NODETOOL_OPTION|-h ::FFFF:127.0.0.1|g' ${playbook}
    else
        sed -i "s|NODETOOL_OPTION||g" ${playbook}
    fi

    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function backup {
    expName=$1
    targetScheme=$2
    kvNumber=$3
    keylength=$4
    fieldlength=$5
    rf=$6
    sstableSize=$7
    compactionStrategy=$8

    echo "Start copy data of ${targetScheme} to backup, this will kill the online system!!!"


    # Copy playbook
    resetPlaybook "backup"
    playbook="playbook-backup.yaml"

    # Modify playbook
    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|PATH_TO_SCRIPTS|${PathToScripts}|g" ${playbook}
    sed -i "s|PATH_TO_BACKUP|${PathToBackup}|g" ${playbook}
    sed -i "s/Scheme/${targetScheme}/g" ${playbook}
    sed -i "s/DATAPATH/${expName}-kvNumber-${kvNumber}-KeySize-${keylength}-ValueSize-${fieldlength}-RF-${rf}-SSTableSize-${sstableSize}-CompactionStrategy-${compactionStrategy}/g" ${playbook}
    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function getSettingName() {
    local motivation=$1
    local compactionLevel=$2

    if [ "$compactionLevel" == "zero" -a "$motivation" == "false" ]; then
        echo "RunA"
    elif [ "$compactionLevel" == "zero" -a "$motivation" == "true" ]; then
        echo "RunB"
    elif [ "$compactionLevel" == "one" -a "$motivation" == "false" ]; then
        echo "RunC"
    elif [ "$compactionLevel" == "one" -a "$motivation" == "true" ]; then
        echo "RunD"
    elif [ "$compactionLevel" == "all" -a "$motivation" == "false" ]; then
        echo "RunE"
    elif [ "$compactionLevel" == "all" -a "$motivation" == "true" ]; then
        echo "RunF"
    fi
}


function copyDatasetToNodes {
    
    experiment=$1
    targetScheme=$2
    kvNumber=$3
    keylength=$4
    fieldlength=$5
    rf=$6
    compactionLevel=$7
    purpose=$8

    datasetName="LoadDB-kvNumber-${kvNumber}-KeySize-${keylength}-ValueSize-${fieldlength}-RF-${rf}"
    targetDir="${PathToBackup}/${targetScheme}/${datasetName}"
    datasetDir=""

    if [ "${purpose}" == "CompactionOverhead" ]; then
        datasetDir="${datasetName}"
    elif [ "${purpose}" == "ReadAmplification" ]; then
        datasetDir="${datasetName}-CompactionLevel-${compactionLevel}"
    fi




    # copy playbook
    resetPlaybook "decompress"

    if [ "${experiment}" == "Exp-MixedReadWrite" ]; then
        for node in "${Servers[@]}"; do
            dataset="${datasetDir}/${node}.tar.gz"
            echo "Copy the dataset ${dataset} to ${node}"
            ssh ${UserName}@${node} 'pkill -f CassandraDaemon'
            ssh ${UserName}@${node} "rm -rf ${targetDir}/data"
            ssh ${UserName}@${node} "rm -rf ${targetDir}/*.tar.gz"
            ssh ${UserName}@${node} "rm -rf ${PathToServer}/data"
            scp -r ${PathToBackup}/${targetScheme}/${dataset} ${UserName}@${node}:${targetDir}
        done
        sed -i "s|DECOMPRESS_DIR|${targetDir}|g" playbook-decompress.yaml
    elif [ "${experiment}" == "Exp-PureRead" ]; then
        for node in "${Servers[@]}"; do
            dataset="${datasetDir}/${node}.tar.gz"
            echo "Copy the dataset ${dataset} to ${node}"
            ssh ${UserName}@${node} 'pkill -f CassandraDaemon'
            ssh ${UserName}@${node} "rm -rf ${targetDir}/data"
            ssh ${UserName}@${node} "rm -rf ${targetDir}/*.tar.gz"
            ssh ${UserName}@${node} "rm -rf ${PathToServer}/data"
            scp -r ${PathToBackup}/${targetScheme}/${dataset} ${UserName}@${node}:${targetDir}
        done
        sed -i "s|DECOMPRESS_DIR|${PathToServer}|g" playbook-decompress.yaml
    fi

    sleep 60


    # Modify playbook
    sed -i "s|TARGET_DIR|${targetDir}|g" playbook-decompress.yaml 

    ansible-playbook -v -i hosts.ini playbook-decompress.yaml
}

function reloadSeeds {
    targetScheme=$1
    resetPlaybook "reloadSeeds"
    playbook="playbook-reloadSeeds.yaml"

    # antOption="-Duse.jdk11=true"

    # if [ "${targetScheme}" == "depart" ] || [ "$targetScheme" == "cassandra-3.11.4" ]; then
    antOption=""
    # fi

    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function rebuildServer {
    
    branch=$1
    targetScheme=$2
    echo "Building the server with branch ${branch}"
    resetPlaybook "rebuildServer"
    playbook="playbook-rebuildServer.yaml"

    # antOption="-Duse.jdk11=true"

    # if [ "${targetScheme}" == "depart" ] || [ "$targetScheme" == "cassandra-3.11.4" ]; then
    antOption=""
    # fi

    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|BRANCH_NAME|${branch}|g" ${playbook}
    sed -i "s|ANT_OPTION|${antOption}|g" ${playbook}
    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function rebuildClient {
    branch=$1
    resetPlaybook "rebuildClient"

    playbook="playbook-rebuildClient.yaml"
    sed -i "s|PATH_TO_CLIENT|${PathToClient}|g" ${playbook}
    sed -i "s|BRANCH_NAME|${branch}|g" ${playbook}
    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function loadDataset {

    expName=$1
    local targetScheme=$2
    kvNumber=$3
    keylength=$4
    fieldlength=$5
    rf=$6
    sstableSize=$7
    compactionStrategy=$8

    if [ "${targetScheme}" == "hats" ] || [ "${targetScheme}" == "c3" ]; then
        targetScheme="mlsm"
    fi
    # Copy playbook
    resetPlaybook "loadDataset"
    playbook="playbook-loadDataset.yaml"
    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|PATH_TO_BACKUP|${PathToBackup}|g" ${playbook}
    sed -i "s/Scheme/${targetScheme}/g" ${playbook}
    sed -i "s/DATAPATH/LoadDB-kvNumber-${kvNumber}-KeySize-${keylength}-ValueSize-${fieldlength}-RF-${rf}-SSTableSize-${sstableSize}-CompactionStrategy-${compactionStrategy}/g" ${playbook}

    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function startFromBackup {
    expName=$1
    targetScheme=$2
    kvNumber=$3
    keylength=$4
    fieldlength=$5
    rf=$6
    memtable_heap_space=$7
    motivation=$8
    shift 8
    rebuild=$1
    useDirectIO=$2
    logLevel=$3
    branch=$4
    schedulingInitialDelay=$5
    schedulingInterval=$6
    statesUpdateInterval=$7
    readSensitivity=$8
    enableHats=$9
    shift 9
    throttleDataRate=$1
    sstableSize=$2
    compactionStrategy=$3
    enableFineSchedule=$4
    enableBackgroundSchedule=$5



    # Copy playbook
    resetPlaybook "startup"
    playbook="playbook-startup.yaml"

    # We use the same dataset for hats and mlsm
    if [ "${targetScheme}" == "hats" ] || [ "${targetScheme}" == "c3" ]; then
        targetScheme="mlsm"
    fi


    echo "Startup the system from backup, motivation is ${motivation}, rebuild is ${rebuild}, useDirectIO is ${useDirectIO}, branch is ${branch}, schedulingInitialDelay is ${schedulingInitialDelay}, schedulingInterval is ${schedulingInterval}, statesUpdateInterval is ${statesUpdateInterval}, readSensitivity is ${readSensitivity}, enableHats is ${enableHats}, throttleDataRate is ${throttleDataRate}, enableFineSchedule is ${enableFineSchedule}, enableBackgroundSchedule is ${enableBackgroundSchedule}" 
    # Modify playbook
    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|PATH_TO_SCRIPTS|${PathToScripts}|g" ${playbook}
    sed -i "s|PATH_TO_BACKUP|${PathToBackup}|g" ${playbook}
    sed -i "s/Scheme/${targetScheme}/g" ${playbook}

    # if [ "$BACKUP_MODE" == "local" ]; then
    #     sed -i "s|DATAPATH|${expName}-kvNumber-${kvNumber}-KeySize-${keylength}-ValueSize-${fieldlength}-RF-${rf}-CompactionLevel-${compactionLevel}|g" ${playbook}
    # elif [ "$BACKUP_MODE" == "remote" ]; then
    #     sed -i "s|DATAPATH|${expName}-kvNumber-${kvNumber}-KeySize-${keylength}-ValueSize-${fieldlength}-RF-${rf}|g" ${playbook}
    # fi

    sed -i "s/DATAPATH/${expName}-kvNumber-${kvNumber}-KeySize-${keylength}-ValueSize-${fieldlength}-RF-${rf}-SSTableSize-${sstableSize}-CompactionStrategy-${compactionStrategy}/g" ${playbook}
    sed -i "s/\(memtableSize: \)".*"/memtableSize: ${memtable_heap_space}MiB/" ${playbook}
    sed -i "s/\(motivation: \)".*"/motivation: \"${motivation}\"/" ${playbook}
    sed -i "s/\(rebuild: \)".*"/rebuild: \"${rebuild}\"/" ${playbook}
    sed -i "s/\(useDirectIO: \)".*"/useDirectIO: \"${useDirectIO}\"/" ${playbook}
    sed -i "s/\(branch: \)".*"/branch: \"${branch}\"/" ${playbook}
    sed -i "s|LOG_LEVEL|${logLevel}|g" ${playbook}
    sed -i "s|SUDO_PASSWD|${SudoPassword}|g" ${playbook}
    sed -i "s/\(schedulingInitialDelay: \)".*"/schedulingInitialDelay: ${schedulingInitialDelay}/" ${playbook}
    sed -i "s/\(schedulingInterval: \)".*"/schedulingInterval: ${schedulingInterval}/" ${playbook}
    sed -i "s/\(statesUpdateInterval: \)".*"/statesUpdateInterval: ${statesUpdateInterval}/" ${playbook}
    sed -i "s/\(readSensitivity: \)".*"/readSensitivity: ${readSensitivity}/" ${playbook}
    sed -i "s|ENABLE_HATS|${enableHats}|g" ${playbook}
    sed -i "s|THROTTLE_DATA_RATE|${throttleDataRate}|g" ${playbook}
    sed -i "s|ENABLE_FINE_SCHEDULE|${enableFineSchedule}|g" ${playbook}
    sed -i "s|ENABLE_BACKGROUND_SCHEDULE|${enableBackgroundSchedule}|g" ${playbook}

    
    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function restartCassandra {

    memtable_heap_space=$1
    motivation=$2
    rebuild=$3
    useDirectIO=$4
    logLevel=$5
    branch=$6
    schedulingInitialDelay=$7
    schedulingInterval=$8
    statesUpdateInterval=$9
    shift 9
    readSensitivity=$1
    enableHats=$2
    throttleDataRate=$3
    enableFineSchedule=$4
    enableBackgroundSchedule=$5
    
    # Copy playbook
    resetPlaybook "restartCassandra"
    playbook="playbook-restartCassandra.yaml"

    echo "Restart the server with enableHats ${enableHats}, motivation ${motivation}, rebuild ${rebuild}, useDirectIO ${useDirectIO}, branch ${branch}, schedulingInitialDelay ${schedulingInitialDelay}, schedulingInterval ${schedulingInterval}, statesUpdateInterval ${statesUpdateInterval}, readSensitivity ${readSensitivity}, throttleDataRate ${throttleDataRate}, enableFineSchedule ${enableFineSchedule}, enableBackgroundSchedule ${enableBackgroundSchedule}"

    # Modify playbook
    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|PATH_TO_SCRIPTS|${PathToScripts}|g" ${playbook}
    sed -i "s/\(memtableSize: \)".*"/memtableSize: ${memtable_heap_space}MiB/" ${playbook}
    sed -i "s/\(motivation: \)".*"/motivation: \"${motivation}\"/" ${playbook}
    sed -i "s/\(rebuild: \)".*"/rebuild: \"${rebuild}\"/" ${playbook}
    sed -i "s/\(useDirectIO: \)".*"/useDirectIO: \"${useDirectIO}\"/" ${playbook}
    sed -i "s/\(branch: \)".*"/branch: \"${branch}\"/" ${playbook}
    # sed -i "s|LOG_LEVEL|${logLevel}|g" ${playbook}
    sed -i "s/\(schedulingInitialDelay: \)".*"/schedulingInitialDelay: ${schedulingInitialDelay}/" ${playbook}
    sed -i "s/\(schedulingInterval: \)".*"/schedulingInterval: ${schedulingInterval}/" ${playbook}
    sed -i "s/\(statesUpdateInterval: \)".*"/statesUpdateInterval: ${statesUpdateInterval}/" ${playbook}
    sed -i "s/\(readSensitivity: \)".*"/readSensitivity: ${readSensitivity}/" ${playbook}
    sed -i "s|ENABLE_HATS|${enableHats}|g" ${playbook}
    sed -i "s|THROTTLE_DATA_RATE|${throttleDataRate}|g" ${playbook}
    sed -i "s|ENABLE_FINE_SCHEDULE|${enableFineSchedule}|g" ${playbook}
    sed -i "s|ENABLE_BACKGROUND_SCHEDULE|${enableBackgroundSchedule}|g" ${playbook}

    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function collectResults {

    resultsDir=$1

    if [ -d ${resultsDir} ]; then
        rm -rf ${resultsDir}
    fi

    mkdir -p ${resultsDir}
    
    for server in "${Servers[@]}"; do
        echo "Copy loading stats of ${targetScheme} back, ${server}"
        scp -r ${UserName}@${server}:/home/${UserName}/Results ${resultsDir}/${server}
        ssh ${UserName}@${server} "rm -rf /home/${UserName}/Results && mkdir -p /home/${UserName}/Results"
    done

    for client in "${Clients[@]}"; do
        latest_file=$(ssh "$client" "ls -t $ClientLogDir | head -n 1")
        echo "Copy the latest log file ${latest_file} from ${client}"
        scp ${client}:${ClientLogDir}${latest_file} ${resultsDir}/
    done
}

function getResultsDir
{   
    CLUSTER_NAME=$1
    MODEL=$2
    EXP_NAME=$3
    SETTING=$4
    workload=$5
    requestDist=$6
    compactionLevel=$7
    threadsNum=$8
    schedulingInterval=$9
    shift 9
    round=$1
    enableHats=$2
    throttleDataRate=$3
    operationNumber=$4
    kvNumber=$5
    sstableSize=$6
    compactionStrategy=$7
    local readConsistencyLevel=$8
    local replication_factor=$9
    shift 9
    local valueSize=$1


    # resultsDir="/home/ymren/Results-${CLUSTER_NAME}-${EXP_NAME}/${MODEL}/workload_${workload}-dist_${requestDist}-compactionLevel_${compactionLevel}-threads_${threadsNum}-schedulingInterval-${schedulingInterval}-throttleDataRate_${throttleDataRate}-kvNumber-${kvNumber}-operationNumber_${operationNumber}-sstableSize_${sstableSize}-compactionStrategy-${compactionStrategy}-CL-${readConsistencyLevel}/round_${round}"
    resultsDir="/home/ymren/Results-${CLUSTER_NAME}-${EXP_NAME}/${MODEL}/workload_${workload}-schedulingInterval_${schedulingInterval}-dist_${requestDist}-clients-${threadsNum}-kvNumber_${kvNumber}-operationNumber_${operationNumber}-consistency_${readConsistencyLevel}-rf_${replication_factor}-valueSize_${valueSize}/round_${round}"

    echo ${resultsDir}
}

function load {
    targetScheme=$1
    threads=$2
    sstableSize=$3
    memtable_heap_space=$4
    rf=$5
    workload=$6
    kvNumber=$7
    fieldlength=$8
    keyLength=$9
    shift 9
    compaction_strategy=$1
    logLevel=$2
    branch=$3
    


    echo "Start loading data into ${targetScheme}"

    # Copy playbook
    resetPlaybook "load"
    playbook="playbook-load.yaml"

    # Modify load playbook
    sed -i "s/\(expName: \)".*"/expName: "${ExpName}-${targetScheme}-Load"/" ${playbook}
    sed -i "s/record_count:.*$/record_count: ${kvNumber}/" ${playbook}
    sed -i "s/filed_length:.*$/filed_length: ${fieldlength}/" ${playbook}
    sed -i "s/\(threads: \)".*"/threads: ${threads}/" ${playbook}
    sed -i "s/\(sstable_size_in_mb: \)".*"/sstable_size_in_mb: ${sstableSize}/" ${playbook}
    sed -i "s/\(replication_factor: \)".*"/replication_factor: ${rf}/" ${playbook}
    sed -i "s/\(workload: \)".*"/workload: workloads\/${workload}/" ${playbook}
    sed -i "s/\(mode: \)".*"/mode: ${targetScheme}/" ${playbook}
    sed -i "s/\(compaction_strategy: \)".*"/compaction_strategy: ${compaction_strategy}/" ${playbook}

    sed -i "s/memtable_heap_space=.*$/memtable_heap_space=\"${memtable_heap_space}MiB\" \&\&/" ${playbook}
    sed -i "s/rebuild=.*$/rebuild=\"${rebuild}\" \&\&/" ${playbook}
    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|PATH_TO_CLIENT|${PathToClient}|g" ${playbook}
    sed -i "s|PATH_TO_SCRIPTS|${PathToScripts}|g" ${playbook}
    sed -i "s|COORDINATORS|${Coordinators}|g" ${playbook}
    sed -i "s|NODE_IP|${NodeIP}|g" ${playbook}
    sed -i "s|PATH_TO_RESULT_DIR|${PathToResultDir}|g" ${playbook}
    sed -i "s|LOG_LEVEL|${logLevel}|g" ${playbook}
    sed -i "s|BRANCH|${branch}|g" ${playbook}
    
    if [ $targetScheme == "depart" ] || [ $targetScheme == "cassandra-3.11.4" ]; then
        sed -i 's|NODETOOL_OPTION|-h ::FFFF:127.0.0.1|g' ${playbook}
    else
        sed -i "s|NODETOOL_OPTION||g" ${playbook}
    fi


    ansible-playbook -v -i hosts.ini ${playbook} -f 100

    ## Collect load results
    resultsDir="/home/${UserName}/Results/Load-threads_${threads}-sstSize_${sstableSize}-memSize_${memtableSize}-rf_${rf}-workload_${workload}-compactionStrategy_${compaction_strategy}"
    collectResults ${resultsDir}
    
}

function run {

    targetScheme=$1
    requestDist=$2
    workload=$3
    threads=$4
    kvNumber=$5
    operations=$6
    keyLen=$7
    fieldLen=$8
    enableAutoCompaction=$9
    shift 9
    enableAutoCompactionCFs="$1"
    memoryLimit=$2
    logLevel=$3
    enableHats=$4
    local readConsistencyLevel=$5
    local enableStartProbe=$6

    echo "Run ${targetScheme} with distribution: ${requestDist} workload: ${workload} threads: ${threads} kvNumber: ${kvNumber} operations: ${operations} keyLen: ${keyLen} fieldLen: ${fieldLen} enableAutoCompaction: ${enableAutoCompaction} enableAutoCompactionCFs: ${enableAutoCompactionCFs} memoryLimit: ${memoryLimit} logLevel: ${logLevel} enableHats: ${enableHats} readConsistencyLevel: ${readConsistencyLevel} enableStartProbe: ${enableStartProbe}"

    resetPlaybook "run"
    playbook="playbook-run.yaml"


    # if [ "${workload}" == "motivation" ]; then
    if [ "${targetScheme}" == "cassandra-5.0" ] || [ "${targetScheme}" == "depart-5.0" ]; then
        enableAutoCompactionCFs="usertable"
    else
        enableAutoCompactionCFs="usertable0 usertable1 usertable2"
    fi
    # fi



    # Modify run playbook
    sed -i "s|KEYSPACE|ycsb|g" ${playbook}
    sed -i "s/\(recordNumber: \)".*"/recordNumber: ${kvNumber}/" ${playbook}
    sed -i "s/\(operationNumber: \)".*"/operationNumber: ${operations}/" ${playbook}
    sed -i "s/\(keyLength: \)".*"/keyLength: ${keyLen}/" ${playbook}
    sed -i "s/\(fieldLength: \)".*"/fieldLength: ${fieldLen}/" ${playbook}
    sed -i "s/\(threads: \)".*"/threads: ${threads}/" ${playbook}
    sed -i "s/workload:.*$/workload: workloads\/${workload}/" ${playbook}
    sed -i "s|WORKLOAD|${workload}|g" ${playbook}
    sed -i "s/requestDistribution:.*$/requestDistribution: ${requestDist}/" ${playbook}
    sed -i "s/\(scheme: \)".*"/scheme: ${targetScheme}/" ${playbook}
    sed -i "s|ENABLE_AUTO_COMPACTION|${enableAutoCompaction}|g" ${playbook}
    sed -i "s/ENABL_COMPACTION_CFS/${enableAutoCompactionCFs}/g" ${playbook}
    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}
    sed -i "s|PATH_TO_CLIENT|${PathToClient}|g" ${playbook}
    sed -i "s|PATH_TO_SCRIPTS|${PathToScripts}|g" ${playbook}
    sed -i "s|COORDINATORS|${Coordinators}|g" ${playbook}
    sed -i "s|PATH_TO_RESULT_DIR|${PathToResultDir}|g" ${playbook}
    sed -i "s|DISK_DEVICE|${DiskDevice}|g" ${playbook}
    sed -i "s|NETWORK_DEVICE|${NetworkInterface}|g" ${playbook}
    sed -i "s|SUDO_PASSWD|${SudoPassword}|g" ${playbook}
    sed -i "s|MEMORY_LIMIT|${memoryLimit}|g" ${playbook}
    sed -i "s|LOG_LEVEL|${logLevel}|g" ${playbook}
    sed -i "s|ENABLE_HATS|${enableHats}|g" ${playbook}
    sed -i "s|PATH_TO_LOG_DIR|${PathToLogDir}|g" ${playbook}
    sed -i "s|CONSISTENCY|${readConsistencyLevel}|g" ${playbook}
    sed -i "s|ENABLE_START_PROBE|${enableStartProbe}|g" ${playbook}

    if [ $targetScheme == "depart" ]|| [ $targetScheme == "cassandra-3.11.4" ]; then
        sed -i 's|NODETOOL_OPTION|-h ::FFFF:127.0.0.1|g' ${playbook}
    else
        sed -i "s|NODETOOL_OPTION||g" ${playbook}
    fi
    

    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function perpareJavaEnvironment {
    
    TARGET_SCHEME=$1
    JDK_VERSION=$2

    resetPlaybook "prepareJavaEnv"

    javaVersion="/usr/lib/jvm/java-11-openjdk-amd64/bin/java"
    if [ "${JDK_VERSION}" == "8" ]; then
        javaVersion="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
    elif [ "${JDK_VERSION}" == "11" ]; then
        javaVersion="/usr/lib/jvm/java-11-openjdk-amd64/bin/java"
    elif [ "${JDK_VERSION}" == "17" ]; then
        javaVersion="/usr/lib/jvm/java-17-openjdk-amd64/bin/java"
    fi

    # if [ "${TARGET_SCHEME}" == "depart" ] || [ "${TARGET_SCHEME}" == "cassandra-3.11.4" ]; then
    #     javaVersion="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
    # fi

    sed -i "s|SUDO_PASSWD|${SudoPassword}|g" playbook-prepareJavaEnv.yaml
    sed -i "s|JAVA_VERSION|${javaVersion}|g" playbook-prepareJavaEnv.yaml

    ansible-playbook -v -i hosts.ini playbook-prepareJavaEnv.yaml -f 100

}


function trimSSD {
    

    resetPlaybook "trimSSD"

    playbook="playbook-trimSSD.yaml"

    sed -i "s|SUDO_PASSWD|${SudoPassword}|g" ${playbook}

    ansible-playbook -v -i hosts.ini ${playbook} -f 100
}

function cleanup {
    scheme=$1

    resetPlaybook "cleanup"
    playbook="playbook-cleanup.yaml"

    sed -i "s|PATH_TO_SERVER|${PathToServer}|g" ${playbook}

    ansible-playbook -v -i hosts.ini ${playbook} -f 100

}

function latency_balance {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 创建汇总结果目录
    local summary_dir="/home/${UserName}/Results-${CLUSTER_NAME}-${EXP_NAME}-Summary"
    mkdir -p "${summary_dir}"
    local summary_file="${summary_dir}/latency_balance_${TARGET_SCHEME}.txt"
    
    # 添加表头
    printf "%-15s %-15s %-20s\n" "Scheme" "Workload" "Avg CoV" | tee "${summary_file}"
    printf "%s\n" "------------------------------------------------" | tee -a "${summary_file}"

    # 遍历所有workload
    for workload in "${ALL_WORKLOADS[@]}"; do
        
        # 存储当前workload所有配置的CoV值
        declare -a all_covs=()
        
        # 遍历配置
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for rf in "${REPLICAS[@]}"; do
                for threadsNum in "${THREAD_NUMBER[@]}"; do
                    for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                        for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                            for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                for fieldLength in "${FIELD_LENGTH[@]}"; do
                                    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                                        
                                        # 存储所有round的CoV值
                                        declare -a round_covs=()
                                        
                                        # 遍历所有rounds
                                        for round in $(seq 1 ${ROUNDS}); do
                                            # 获取结果目录
                                            resultsDir=$(getResultsDir "${CLUSTER_NAME}" "${TARGET_SCHEME}" "${EXP_NAME}" "RunE" "${workload}" "${dist}" "all" "${threadsNum}" "${schedulingInterval}" "${round}" "false" "${throttleDataRate}" "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" "${consistency}" "${rf}" "${fieldLength}")
                                            
                                            # 收集当前round所有节点的coordinator_read_time
                                            declare -a coordinator_read_times=()
                                            declare -a coordinator_read_counts=()
                                            
                                            # 遍历所有节点目录
                                            for node_dir in "${resultsDir}"/node*; do
                                                if [ -d "${node_dir}" ]; then
                                                    breakdown_file="${node_dir}/metrics/breakdown.txt"
                                                    
                                                    if [ -f "${breakdown_file}" ]; then
                                                        # 提取coordinator_read_time和count
                                                        coordinator_read_count=$(grep "Coordinator read count" "${breakdown_file}" | awk '{print $NF}')
                                                        coordinator_read_time=$(grep "Local read latency" "${breakdown_file}" | awk '{print $NF}')
                                                        
                                                        if [ -n "${coordinator_read_count}" ] && [ -n "${coordinator_read_time}" ] && [ "${coordinator_read_count}" != "0" ]; then
                                                            # print values for debug
                                                            # echo "Node: ${node_dir}, Coordinator Read Count: ${coordinator_read_count}, Coordinator Read Time: ${coordinator_read_time}"
                                                            # 计算平均时间 (微秒)
                                                            # avg_time=$(echo "scale=2; ${coordinator_read_time} / ${coordinator_read_count}" | bc)
                                                            coordinator_read_times+=("${coordinator_read_time}")
                                                        fi
                                                    fi
                                                fi
                                            done
                                            
                                            # 计算当前round的CoV
                                            if [ ${#coordinator_read_times[@]} -gt 0 ]; then
                                                round_cov=$(calculate_cov coordinator_read_times[@])
                                                round_covs+=("${round_cov}")
                                            fi
                                            
                                            unset coordinator_read_times
                                        done
                                        
                                        # 计算当前配置的平均CoV
                                        if [ ${#round_covs[@]} -gt 0 ]; then
                                            avg_cov=$(calculate_average round_covs[@])
                                            all_covs+=("${avg_cov}")
                                        fi
                                        
                                        unset round_covs
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        
        # 计算workload的总体平均CoV
        if [ ${#all_covs[@]} -gt 0 ]; then
            final_cov=$(calculate_average all_covs[@])
            
            # 输出到屏幕和文件
            printf "%-15s %-15s %-20s\n" \
                "${TARGET_SCHEME}" "${workload}" "${final_cov}" | tee -a "${summary_file}"
        fi
        
        unset all_covs
    done
    
    echo ""
}

# 复用现有的 calculate_cov 函数
function calculate_cov() {
    local data=("${!1}")
    local sum=0
    local sum_of_squares=0
    local mean=0
    local std_dev=0
    local cov=0

    # 计算总和
    for value in "${data[@]}"; do
        sum=$(echo "${sum} + ${value}" | bc)
    done

    # 计算平均值
    mean=$(echo "scale=6; ${sum} / ${#data[@]}" | bc)

    # 计算平方和
    for value in "${data[@]}"; do
        diff=$(echo "${value} - ${mean}" | bc)
        square=$(echo "${diff} * ${diff}" | bc)
        sum_of_squares=$(echo "${sum_of_squares} + ${square}" | bc)
    done

    # 计算标准差
    std_dev=$(echo "scale=6; sqrt(${sum_of_squares} / ${#data[@]})" | bc)

    # 计算变异系数
    if [ "$(echo "${mean} > 0" | bc)" -eq 1 ]; then
        cov=$(echo "scale=6; (${std_dev}) / ${mean}" | bc)
    else
        cov="0"
    fi

    echo "${cov}"
}

function performance_breakdown {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 创建汇总结果目录
    local summary_dir="/home/${UserName}/Results-${CLUSTER_NAME}-${EXP_NAME}-Summary"
    mkdir -p "${summary_dir}"
    local summary_file="${summary_dir}/performance_breakdown_${TARGET_SCHEME}.txt"
    
    # 添加表头
    printf "%-12s %-12s %-18s %-18s %-18s %-18s %-18s %-18s %-18s %-18s\n" \
        "Scheme" "Workload" "WAL(us)" "WriteMemTable(us)" "Flushing(us)" "Compaction(us)" \
        "Selection(us)" "ReadMemTable(us)" "Caches(us)" "Disk(us)" | tee "${summary_file}"
    printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------" | tee -a "${summary_file}"

    # 遍历所有workload
    for workload in "${ALL_WORKLOADS[@]}"; do

        if [ "${workload}" != "workloada" ] && [ "${workload}" != "workloadc" ]; then
            continue
        fi
        
        declare -a all_local_read_times=()
        declare -a all_selection_times=()
        declare -a all_write_memtable_times=()
        declare -a all_write_wal_times=()
        declare -a all_flush_times=()
        declare -a all_compaction_times=()
        declare -a all_read_cache_times=()
        declare -a all_read_memtable_times=()
        declare -a all_read_sstable_times=()
        
        # 遍历配置
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for rf in "${REPLICAS[@]}"; do
                for threadsNum in "${THREAD_NUMBER[@]}"; do
                    for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                        for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                            for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                for fieldLength in "${FIELD_LENGTH[@]}"; do
                                    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                                        
                                        declare -a round_local_read_times=()
                                        declare -a round_selection_times=()
                                        declare -a round_write_memtable_times=()
                                        declare -a round_write_wal_times=()
                                        declare -a round_flush_times=()
                                        declare -a round_compaction_times=()
                                        declare -a round_read_cache_times=()
                                        declare -a round_read_memtable_times=()
                                        declare -a round_read_sstable_times=()
                                        
                                        # 遍历所有rounds
                                        for round in $(seq 1 ${ROUNDS}); do
                                            resultsDir=$(getResultsDir "${CLUSTER_NAME}" "${TARGET_SCHEME}" "${EXP_NAME}" "RunE" "${workload}" "${dist}" "all" "${threadsNum}" "${schedulingInterval}" "${round}" "false" "${throttleDataRate}" "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" "${consistency}" "${rf}" "${fieldLength}")
                                            
                                            # 收集当前round所有节点的数据
                                            declare -a coordinator_read_counts=()
                                            declare -a coordinator_read_times=()
                                            declare -a local_read_counts=()
                                            declare -a local_read_times=()
                                            declare -a selection_times=()
                                            declare -a local_write_counts=()
                                            declare -a write_memtable_times=()
                                            declare -a write_wal_times=()
                                            declare -a flush_times=()
                                            declare -a compaction_times=()
                                            declare -a read_cache_times=()
                                            declare -a read_memtable_times=()
                                            declare -a read_sstable_times=()
                                            
                                            # 遍历所有节点目录
                                            for node_dir in "${resultsDir}"/node*; do
                                                if [ -d "${node_dir}" ]; then
                                                    breakdown_file="${node_dir}/metrics/breakdown.txt"
                                                    
                                                    if [ -f "${breakdown_file}" ]; then
                                                        # 提取count和总时间(毫秒)
                                                        local_read_count=$(grep "Local read count" "${breakdown_file}" | awk '{print $NF}')
                                                        coordinator_read_count=$(grep "Coordinator read count" "${breakdown_file}" | awk '{print $NF}')
                                                        local_write_count=$(grep "Local write count" "${breakdown_file}" | awk '{print $NF}')
                                                        
                                                        coordinator_read_time_ms=$(grep "CoordinatorReadTime" "${breakdown_file}" | awk '{print $NF}')
                                                        local_read_time_ms=$(grep "LocalReadTime" "${breakdown_file}" | awk '{print $NF}')
                                                        write_memtable_time_ms=$(grep "WriteMemTable" "${breakdown_file}" | awk '{print $NF}')
                                                        write_wal_time_ms=$(grep "CommitLog" "${breakdown_file}" | awk '{print $NF}')
                                                        flush_time_ms=$(grep "Flush" "${breakdown_file}" | awk '{print $NF}')
                                                        compaction_time_ms=$(grep "Compaction" "${breakdown_file}" | awk '{print $NF}')
                                                        read_cache_time_ms=$(grep "ReadCache" "${breakdown_file}" | awk '{print $NF}')
                                                        read_memtable_time_ms=$(grep "ReadMemTable" "${breakdown_file}" | awk '{print $NF}')
                                                        read_sstable_time_ms=$(grep "ReadSSTable" "${breakdown_file}" | awk '{print $NF}')
                                                        
                                                        # 计算每个节点的平均时间(微秒) = 总时间(ms) * 1000 / count
                                                        if [ -n "${coordinator_read_count}" ] && [ "${coordinator_read_count}" -gt 0 ]; then
                                                            coord_read_time=$(echo "scale=0; ${coordinator_read_time_ms:-0} / ${coordinator_read_count}" | bc)
                                                            local_read_time=$(echo "scale=0; ${local_read_time_ms:-0} / ${local_read_count}" | bc)
                                                            selection_time=$(echo "scale=0; ${coord_read_time} - ${local_read_time}" | bc)
                                                            
                                                            coordinator_read_counts+=("${coordinator_read_count}")
                                                            coordinator_read_times+=("${coord_read_time}")
                                                            local_read_counts+=("${local_read_count}")
                                                            local_read_times+=("${local_read_time}")
                                                            selection_times+=("${selection_time}")
                                                        fi
                                                        
                                                        if [ -n "${local_write_count}" ] && [ "${local_write_count}" -gt 0 ]; then
                                                            write_memtable_time=$(echo "scale=0; ${write_memtable_time_ms:-0} / ${local_write_count}" | bc)
                                                            write_wal_time=$(echo "scale=0; ${write_wal_time_ms:-0} / ${local_write_count}" | bc)
                                                            flush_time=$(echo "scale=0; ${flush_time_ms:-0} / ${local_write_count}" | bc)
                                                            compaction_time=$(echo "scale=0; ${compaction_time_ms:-0} / ${local_write_count}" | bc)
                                                            
                                                            local_write_counts+=("${local_write_count}")
                                                            write_memtable_times+=("${write_memtable_time}")
                                                            write_wal_times+=("${write_wal_time}")
                                                            flush_times+=("${flush_time}")
                                                            compaction_times+=("${compaction_time}")
                                                        fi
                                                        
                                                        if [ -n "${local_read_count}" ] && [ "${local_read_count}" -gt 0 ]; then
                                                            read_cache_time=$(echo "scale=0; ${read_cache_time_ms:-0} / ${local_read_count}" | bc)
                                                            read_memtable_time=$(echo "scale=0; ${read_memtable_time_ms:-0} / ${local_read_count}" | bc)
                                                            read_sstable_time=$(echo "scale=0; ${read_sstable_time_ms:-0} / ${local_read_count}" | bc)
                                                            
                                                            read_cache_times+=("${read_cache_time}")
                                                            read_memtable_times+=("${read_memtable_time}")
                                                            read_sstable_times+=("${read_sstable_time}")
                                                        fi
                                                    fi
                                                fi
                                            done
                                            
                                            # 使用加权平均计算当前round的结果
                                            if [ ${#local_read_times[@]} -gt 0 ]; then
                                                round_local_read=$(calculate_weighted_average local_read_counts[@] local_read_times[@])
                                                round_selection=$(calculate_weighted_average coordinator_read_counts[@] selection_times[@])
                                                round_read_cache=$(calculate_weighted_average local_read_counts[@] read_cache_times[@])
                                                round_read_memtable=$(calculate_weighted_average local_read_counts[@] read_memtable_times[@])
                                                round_read_sstable=$(calculate_weighted_average local_read_counts[@] read_sstable_times[@])
                                                
                                                round_local_read_times+=("${round_local_read}")
                                                round_selection_times+=("${round_selection}")
                                                round_read_cache_times+=("${round_read_cache}")
                                                round_read_memtable_times+=("${round_read_memtable}")
                                                round_read_sstable_times+=("${round_read_sstable}")
                                            fi
                                            
                                            if [ ${#write_memtable_times[@]} -gt 0 ]; then
                                                round_write_memtable=$(calculate_weighted_average local_write_counts[@] write_memtable_times[@])
                                                round_write_wal=$(calculate_weighted_average local_write_counts[@] write_wal_times[@])
                                                round_flush=$(calculate_weighted_average local_write_counts[@] flush_times[@])
                                                round_compaction=$(calculate_weighted_average local_write_counts[@] compaction_times[@])
                                                
                                                round_write_memtable_times+=("${round_write_memtable}")
                                                round_write_wal_times+=("${round_write_wal}")
                                                round_flush_times+=("${round_flush}")
                                                round_compaction_times+=("${round_compaction}")
                                            fi
                                            
                                            unset coordinator_read_counts coordinator_read_times local_read_counts local_read_times
                                            unset selection_times local_write_counts write_memtable_times write_wal_times
                                            unset flush_times compaction_times read_cache_times read_memtable_times read_sstable_times
                                        done
                                        
                                        # 计算当前配置的平均值(对所有round求平均)
                                        if [ ${#round_local_read_times[@]} -gt 0 ]; then
                                            all_local_read_times+=("$(calculate_average round_local_read_times[@])")
                                            all_selection_times+=("$(calculate_average round_selection_times[@])")
                                            all_read_cache_times+=("$(calculate_average round_read_cache_times[@])")
                                            all_read_memtable_times+=("$(calculate_average round_read_memtable_times[@])")
                                            all_read_sstable_times+=("$(calculate_average round_read_sstable_times[@])")
                                        fi
                                        
                                        if [ ${#round_write_memtable_times[@]} -gt 0 ]; then
                                            all_write_memtable_times+=("$(calculate_average round_write_memtable_times[@])")
                                            all_write_wal_times+=("$(calculate_average round_write_wal_times[@])")
                                            all_flush_times+=("$(calculate_average round_flush_times[@])")
                                            all_compaction_times+=("$(calculate_average round_compaction_times[@])")
                                        fi
                                        
                                        unset round_local_read_times round_selection_times round_write_memtable_times
                                        unset round_write_wal_times round_flush_times round_compaction_times
                                        unset round_read_cache_times round_read_memtable_times round_read_sstable_times
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        
        # 计算workload的总体平均值
        final_local_read=$(calculate_average all_local_read_times[@])
        final_selection=$(calculate_average all_selection_times[@])
        final_write_memtable=$(calculate_average all_write_memtable_times[@])
        final_write_wal=$(calculate_average all_write_wal_times[@])
        final_flush=$(calculate_average all_flush_times[@])
        final_compaction=$(calculate_average all_compaction_times[@])
        final_read_cache=$(calculate_average all_read_cache_times[@])
        final_read_memtable=$(calculate_average all_read_memtable_times[@])
        final_read_sstable=$(calculate_average all_read_sstable_times[@])
        
        # 输出到屏幕和文件
        # printf "%-12s %-12s %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f\n" \
        #     "${TARGET_SCHEME}" "${workload}" "${final_local_read}" "${final_selection}" "${final_write_memtable}" \
        #     "${final_write_wal}" "${final_flush}" "${final_compaction}" "${final_read_cache}" \
        #     "${final_read_memtable}" "${final_read_sstable}" | tee -a "${summary_file}"
        
        printf "%-12s %-12s %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f %-18.0f\n" \
            "${TARGET_SCHEME}" "${workload}" "${final_write_wal}" "${final_write_memtable}" "${final_flush}" \
            "${final_compaction}" "${final_selection}" "${final_read_memtable}" "${final_read_cache}" \
            "${final_read_sstable}" | tee -a "${summary_file}"
        unset all_local_read_times all_selection_times all_write_memtable_times
        unset all_write_wal_times all_flush_times all_compaction_times
        unset all_read_cache_times all_read_memtable_times all_read_sstable_times
    done
    
    echo ""
}

# 辅助函数: 计算加权平均值 (等同于 processResult.sh 中的 calculate_arithmetic_mean)
function calculate_weighted_average {
    local count_array=("${!1}")
    local value_array=("${!2}")
    
    local num_attributes="${#count_array[@]}"
    
    if [ "$num_attributes" -ne "${#value_array[@]}" ]; then
        echo "0"
        return
    fi
    
    local total_sum=0
    local total_count=0
    
    for ((i=0; i<num_attributes; i++)); do
        local count="${count_array[$i]}"
        local value="${value_array[$i]}"
        
        if ! [[ "$count" =~ ^[0-9]+$ ]]; then
            continue
        fi
        
        if ! [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            continue
        fi
        
        local sum=$(echo "scale=0; $count * $value" | bc)
        total_sum=$(echo "scale=0; $total_sum + $sum" | bc)
        total_count=$((total_count + count))
    done
    
    if [ "$total_count" -eq 0 ]; then
        echo "0"
        return
    fi
    
    local arithmetic_mean=$(echo "scale=0; $total_sum / $total_count" | bc)
    echo "$arithmetic_mean"
}


function resource_usage {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 创建汇总结果目录
    local summary_dir="/home/${UserName}/Results-${CLUSTER_NAME}-${EXP_NAME}-Summary"
    mkdir -p "${summary_dir}"
    local summary_file="${summary_dir}/resource_usage_${TARGET_SCHEME}.txt"
    
    # 添加表头
    printf "%-12s %-12s %-18s %-18s %-18s %-18s\n" \
        "Scheme" "Workload" "DiskIO(MiB)" "NetworkIO(MiB)" "CPU(s)" "Memory(GiB)" | tee "${summary_file}"
    printf "%s\n" "------------------------------------------------------------------------------------" | tee -a "${summary_file}"

    # 遍历所有workload
    for workload in "${ALL_WORKLOADS[@]}"; do
        if [ "${workload}" != "workloada" ] && [ "${workload}" != "workloadb" ] && [ "${workload}" != "workloadc" ]; then
            continue
        fi
        
        declare -a all_disk_io=()
        declare -a all_network_io=()
        declare -a all_cpu_time=()
        declare -a all_mem_size=()
        
        # 遍历配置
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for rf in "${REPLICAS[@]}"; do
                for threadsNum in "${THREAD_NUMBER[@]}"; do
                    for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                        for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                            for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                for fieldLength in "${FIELD_LENGTH[@]}"; do
                                    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                                        
                                        declare -a round_disk_io=()
                                        declare -a round_network_io=()
                                        declare -a round_cpu_time=()
                                        declare -a round_mem_size=()
                                        
                                        # 遍历所有rounds
                                        for round in $(seq 1 ${ROUNDS}); do
                                            resultsDir=$(getResultsDir "${CLUSTER_NAME}" "${TARGET_SCHEME}" "${EXP_NAME}" "RunE" "${workload}" "${dist}" "all" "${threadsNum}" "${schedulingInterval}" "${round}" "false" "${throttleDataRate}" "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" "${consistency}" "${rf}" "${fieldLength}")
                                            
                                            # 收集当前round所有节点的资源使用数据
                                            declare -a overall_disk_io_of_all_nodes=()
                                            declare -a overall_network_io_of_all_nodes=()
                                            declare -a overall_cpu_time_of_all_nodes=()
                                            declare -a mem_size_of_all_nodes=()
                                            
                                            # 遍历所有节点目录
                                            for node_dir in "${resultsDir}"/node*; do
                                                if [ -d "${node_dir}" ]; then
                                                    # 读取CPU时间
                                                    cpu_file="${node_dir}/metrics/After-normal-run_cpu_summary.txt"
                                                    if [ -f "${cpu_file}" ]; then
                                                        user_time=$(grep "User time" "${cpu_file}" | awk '{printf "%.0f", $NF}')
                                                        sys_time=$(grep "System time" "${cpu_file}" | awk '{printf "%.0f", $NF}')
                                                        overall_cpu_time=$(echo "scale=0; ${user_time:-0} + ${sys_time:-0}" | bc)
                                                        overall_cpu_time_of_all_nodes+=("${overall_cpu_time}")
                                                    fi
                                                    
                                                    # 读取磁盘IO
                                                    disk_io_after="${node_dir}/metrics/After-normal-run_disk_io_total.txt"
                                                    disk_io_before="${node_dir}/metrics/Before-run_disk_io_total.txt"
                                                    if [ -f "${disk_io_after}" ] && [ -f "${disk_io_before}" ]; then
                                                        after_read=$(grep "Disk KiB read" "${disk_io_after}" | awk '{printf "%f", $NF}')
                                                        before_read=$(grep "Disk KiB read" "${disk_io_before}" | awk '{printf "%f", $NF}')
                                                        disk_read_io=$(echo "scale=0; (${after_read:-0} - ${before_read:-0}) / 1024" | bc)
                                                        
                                                        after_written=$(grep "Disk KiB written" "${disk_io_after}" | awk '{printf "%f", $NF}')
                                                        before_written=$(grep "Disk KiB written" "${disk_io_before}" | awk '{printf "%f", $NF}')
                                                        disk_write_io=$(echo "scale=0; (${after_written:-0} - ${before_written:-0}) / 1024" | bc)
                                                        
                                                        overall_disk_io=$(echo "scale=0; ${disk_read_io} + ${disk_write_io}" | bc)
                                                        overall_disk_io_of_all_nodes+=("${overall_disk_io}")
                                                    fi
                                                    
                                                    # 读取网络IO
                                                    network_after="${node_dir}/metrics/After-normal-run_network_summary.txt"
                                                    network_before="${node_dir}/metrics/Before-run_network_summary.txt"
                                                    if [ -f "${network_after}" ] && [ -f "${network_before}" ]; then
                                                        after_received=$(grep "Bytes received" "${network_after}" | awk '{printf "%f", $NF}')
                                                        before_received=$(grep "Bytes received" "${network_before}" | awk '{printf "%f", $NF}')
                                                        network_recv_io=$(echo "scale=0; (${after_received:-0} - ${before_received:-0}) / 1048576" | bc)
                                                        
                                                        after_sent=$(grep "Bytes sent" "${network_after}" | awk '{printf "%f", $NF}')
                                                        before_sent=$(grep "Bytes sent" "${network_before}" | awk '{printf "%f", $NF}')
                                                        network_send_io=$(echo "scale=0; (${after_sent:-0} - ${before_sent:-0}) / 1048576" | bc)
                                                        
                                                        overall_network_io=$(echo "scale=0; ${network_recv_io} + ${network_send_io}" | bc)
                                                        overall_network_io_of_all_nodes+=("${overall_network_io}")
                                                    fi
                                                    
                                                    # 读取内存使用 - 调用 calculate_average_memory_usage 函数
                                                    mem_file="${node_dir}/metrics/SampleExpName_Running_memory_usage.txt"
                                                    if [ -f "${mem_file}" ]; then
                                                        mem_size=$(calculate_average_memory_usage "${mem_file}")
                                                        mem_size_of_all_nodes+=("${mem_size}")
                                                    fi
                                                fi
                                            done
                                            
                                            # 计算当前round所有节点的平均值
                                            if [ ${#overall_disk_io_of_all_nodes[@]} -gt 0 ]; then
                                                avg_disk_io=$(echo "scale=0; ($(IFS=+; echo "${overall_disk_io_of_all_nodes[*]}")) / ${#overall_disk_io_of_all_nodes[@]}" | bc)
                                                round_disk_io+=("${avg_disk_io}")
                                            fi
                                            
                                            if [ ${#overall_network_io_of_all_nodes[@]} -gt 0 ]; then
                                                avg_network_io=$(echo "scale=0; ($(IFS=+; echo "${overall_network_io_of_all_nodes[*]}")) / ${#overall_network_io_of_all_nodes[@]}" | bc)
                                                round_network_io+=("${avg_network_io}")
                                            fi
                                            
                                            if [ ${#overall_cpu_time_of_all_nodes[@]} -gt 0 ]; then
                                                avg_cpu_time=$(echo "scale=0; ($(IFS=+; echo "${overall_cpu_time_of_all_nodes[*]}")) / ${#overall_cpu_time_of_all_nodes[@]}" | bc)
                                                round_cpu_time+=("${avg_cpu_time}")
                                            fi
                                            
                                            if [ ${#mem_size_of_all_nodes[@]} -gt 0 ]; then
                                                avg_mem_size=$(echo "scale=2; ($(IFS=+; echo "${mem_size_of_all_nodes[*]}")) / ${#mem_size_of_all_nodes[@]}" | bc)
                                                round_mem_size+=("${avg_mem_size}")
                                            fi
                                            
                                            unset overall_disk_io_of_all_nodes overall_network_io_of_all_nodes
                                            unset overall_cpu_time_of_all_nodes mem_size_of_all_nodes
                                        done
                                        
                                        # 计算当前配置的平均值(对所有round求平均)
                                        if [ ${#round_disk_io[@]} -gt 0 ]; then
                                            all_disk_io+=("$(calculate_average round_disk_io[@])")
                                        fi
                                        
                                        if [ ${#round_network_io[@]} -gt 0 ]; then
                                            all_network_io+=("$(calculate_average round_network_io[@])")
                                        fi
                                        
                                        if [ ${#round_cpu_time[@]} -gt 0 ]; then
                                            all_cpu_time+=("$(calculate_average round_cpu_time[@])")
                                        fi
                                        
                                        if [ ${#round_mem_size[@]} -gt 0 ]; then
                                            all_mem_size+=("$(calculate_average round_mem_size[@])")
                                        fi
                                        
                                        unset round_disk_io round_network_io round_cpu_time round_mem_size
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        
        # 计算workload的总体平均值
        final_disk_io=$(calculate_average all_disk_io[@])
        final_network_io=$(calculate_average all_network_io[@])
        final_cpu_time=$(calculate_average all_cpu_time[@])
        final_mem_size=$(calculate_average all_mem_size[@])
        
        # 输出到屏幕和文件
        printf "%-12s %-12s %-18.0f %-18.0f %-18.0f %-18.2f\n" \
            "${TARGET_SCHEME}" "${workload}" "${final_disk_io}" "${final_network_io}" \
            "${final_cpu_time}" "${final_mem_size}" | tee -a "${summary_file}"
        
        unset all_disk_io all_network_io all_cpu_time all_mem_size
    done
    
    echo ""
}

# 添加 calculate_average_memory_usage 函数 (从 processResult.sh 复制)
function calculate_average_memory_usage() {
    local file="$1"
    local total_gib=0
    local count=0

    while read -r line; do
        memory_kib=$(echo "$line" | grep -oP 'using \K[0-9]+')

        if [ -n "$memory_kib" ]; then
            memory_gib=$(echo "scale=6; $memory_kib / (1024 * 1024)" | bc)
            total_gib=$(echo "$total_gib + $memory_gib" | bc)
            count=$((count + 1))
        fi
    done < "$file"

    if [ $count -gt 0 ]; then
        average_gib=$(echo "scale=6; $total_gib / $count" | bc)
        echo "$average_gib"
    else
        echo "0"
    fi
}

function analyze_facebook_results {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 创建汇总结果目录
    local summary_dir="/home/${UserName}/Results-${CLUSTER_NAME}-${EXP_NAME}-Summary"
    mkdir -p "${summary_dir}"
    local summary_file="${summary_dir}/facebook_results_${TARGET_SCHEME}.txt"
    
    # 添加表头
    printf "%-15s %-15s %-20s %-20s\n" "Scheme" "Operation" "Average(us)" "P99(us)" | tee "${summary_file}"
    printf "%s\n" "--------------------------------------------------------------------------------" | tee -a "${summary_file}"

    # 定义操作类型 (用于从日志文件中提取)
    local operations=("READ" "UPDATE" "SCAN")
    
    # 定义操作名称映射 (用于输出显示)
    declare -A operation_names
    operation_names["READ"]="Get"
    operation_names["UPDATE"]="Put"
    operation_names["SCAN"]="Seek"

    # 遍历所有workload
    for workload in "${ALL_WORKLOADS[@]}"; do
        
        # 为每个operation类型存储指标
        declare -A all_avg_latencies
        declare -A all_p99_latencies
        
        # 初始化数组
        for op in "${operations[@]}"; do
            all_avg_latencies[$op]=""
            all_p99_latencies[$op]=""
        done
        
        # 遍历配置
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for rf in "${REPLICAS[@]}"; do
                for threadsNum in "${THREAD_NUMBER[@]}"; do
                    for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                        for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                            for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                for fieldLength in "${FIELD_LENGTH[@]}"; do
                                    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                                        
                                        # 为每个operation存储所有round的数据
                                        declare -A round_avg_latencies
                                        declare -A round_p99_latencies
                                        
                                        # 初始化
                                        for op in "${operations[@]}"; do
                                            round_avg_latencies[$op]=""
                                            round_p99_latencies[$op]=""
                                        done
                                        
                                        # 遍历所有rounds
                                        for round in $(seq 1 ${ROUNDS}); do
                                            # 获取结果目录
                                            resultsDir=$(getResultsDir "${CLUSTER_NAME}" "${TARGET_SCHEME}" "${EXP_NAME}" "RunE" "${workload}" "${dist}" "all" "${threadsNum}" "${schedulingInterval}" "${round}" "false" "${throttleDataRate}" "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" "${consistency}" "${rf}" "${fieldLength}")
                                            
                                            # 查找YCSB日志文件
                                            log_file=$(find "${resultsDir}" -maxdepth 1 -name "Run-*proj18*.log" -type f 2>/dev/null | head -n 1)
                                            
                                            if [ -n "${log_file}" ] && [ -f "${log_file}" ]; then
                                                # 为每个operation提取指标
                                                for op in "${operations[@]}"; do
                                                    # 提取平均延迟: [READ], AverageLatency(us), 828.24
                                                    avg_latency=$(grep "^\[${op}\], AverageLatency(us)," "${log_file}" | awk -F', ' '{print $3}')
                                                    
                                                    # 提取P99延迟: [READ], 99thPercentileLatency(us), 1234
                                                    p99_latency=$(grep "^\[${op}\], 99thPercentileLatency(us)," "${log_file}" | awk -F', ' '{print $3}')
                                                    
                                                    # 如果提取到数据,添加到round数组
                                                    if [ -n "${avg_latency}" ] && [ "${avg_latency}" != "0" ]; then
                                                        if [ -z "${round_avg_latencies[$op]}" ]; then
                                                            round_avg_latencies[$op]="${avg_latency}"
                                                        else
                                                            round_avg_latencies[$op]="${round_avg_latencies[$op]} ${avg_latency}"
                                                        fi
                                                    fi
                                                    
                                                    if [ -n "${p99_latency}" ] && [ "${p99_latency}" != "0" ]; then
                                                        if [ -z "${round_p99_latencies[$op]}" ]; then
                                                            round_p99_latencies[$op]="${p99_latency}"
                                                        else
                                                            round_p99_latencies[$op]="${round_p99_latencies[$op]} ${p99_latency}"
                                                        fi
                                                    fi
                                                done
                                            fi
                                        done
                                        
                                        # 计算当前配置的平均值
                                        for op in "${operations[@]}"; do
                                            if [ -n "${round_avg_latencies[$op]}" ]; then
                                                # 将字符串转换为数组并计算平均值
                                                read -ra avg_array <<< "${round_avg_latencies[$op]}"
                                                if [ ${#avg_array[@]} -gt 0 ]; then
                                                    avg=$(calculate_average avg_array[@])
                                                    if [ -z "${all_avg_latencies[$op]}" ]; then
                                                        all_avg_latencies[$op]="${avg}"
                                                    else
                                                        all_avg_latencies[$op]="${all_avg_latencies[$op]} ${avg}"
                                                    fi
                                                fi
                                            fi
                                            
                                            if [ -n "${round_p99_latencies[$op]}" ]; then
                                                read -ra p99_array <<< "${round_p99_latencies[$op]}"
                                                if [ ${#p99_array[@]} -gt 0 ]; then
                                                    p99=$(calculate_average p99_array[@])
                                                    if [ -z "${all_p99_latencies[$op]}" ]; then
                                                        all_p99_latencies[$op]="${p99}"
                                                    else
                                                        all_p99_latencies[$op]="${all_p99_latencies[$op]} ${p99}"
                                                    fi
                                                fi
                                            fi
                                        done
                                        
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        
        # 计算并输出每个operation的最终平均值
        for op in "${operations[@]}"; do
            if [ -n "${all_avg_latencies[$op]}" ]; then
                # 转换为数组并计算总体平均值
                read -ra final_avg_array <<< "${all_avg_latencies[$op]}"
                read -ra final_p99_array <<< "${all_p99_latencies[$op]}"
                
                if [ ${#final_avg_array[@]} -gt 0 ]; then
                    final_avg=$(calculate_average final_avg_array[@])
                    final_p99=$(calculate_average final_p99_array[@])
                    
                    # 使用映射后的操作名称输出
                    display_op="${operation_names[$op]}"
                    
                    # 输出到屏幕和文件
                    printf "%-15s %-15s %-20.2f %-20.2f\n" \
                        "${TARGET_SCHEME}" "${display_op}" "${final_avg}" "${final_p99}" | tee -a "${summary_file}"
                fi
            fi
        done
        
    done
    
    echo ""
}

function analyze_ycsb_results {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 创建汇总结果目录
    local summary_dir="/home/${UserName}/Results-${CLUSTER_NAME}-${EXP_NAME}-Summary"
    mkdir -p "${summary_dir}"
    local summary_file="${summary_dir}/summary_${TARGET_SCHEME}.txt"
    
    # 如果是第一次写入该scheme的文件,添加表头
    # if [ ! -f "${summary_file}" ]; then
    printf "%-15s %-15s %-20s %-15s %-15s %-15s\n" "Scheme" "Workload" "Throughput(ops/s)" "P50(us)" "P99(us)" "P999(us)" | tee "${summary_file}"
    printf "%s\n" "--------------------------------------------------------------------------------" | tee -a "${summary_file}"
    # fi

    # 遍历所有workload
    for workload in "${ALL_WORKLOADS[@]}"; do
        
        # 存储当前workload所有配置的指标值
        declare -a all_throughputs=()
        declare -a all_p50s=()
        declare -a all_p99s=()
        declare -a all_p999s=()
        
        # 遍历配置
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for rf in "${REPLICAS[@]}"; do
                for threadsNum in "${THREAD_NUMBER[@]}"; do
                    for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                        for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                            for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                for fieldLength in "${FIELD_LENGTH[@]}"; do
                                    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                                        
                                        # 存储所有round的指标
                                        declare -a round_throughputs=()
                                        declare -a round_p50s=()
                                        declare -a round_p99s=()
                                        declare -a round_p999s=()
                                        
                                        # 遍历所有rounds
                                        for round in $(seq 1 ${ROUNDS}); do
                                            # 获取结果目录
                                            resultsDir=$(getResultsDir "${CLUSTER_NAME}" "${TARGET_SCHEME}" "${EXP_NAME}" "RunE" "${workload}" "${dist}" "all" "${threadsNum}" "${schedulingInterval}" "${round}" "false" "${throttleDataRate}" "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" "${consistency}" "${rf}" "${fieldLength}")
                                            
                                            # 查找YCSB日志文件
                                            log_file=$(find "${resultsDir}" -maxdepth 1 -name "Run-*proj18*.log" -type f 2>/dev/null | head -n 1)
                                            
                                            if [ -n "${log_file}" ] && [ -f "${log_file}" ]; then
                                                # 提取OVERALL指标
                                                throughput=$(grep "^\[OVERALL\], Throughput(ops/sec)," "${log_file}" | awk -F', ' '{print $3}')
                                                p50=$(grep "^\[OVERALL\], MedianLatency(us)," "${log_file}" | awk -F', ' '{print $3}')
                                                p99=$(grep "^\[OVERALL\], 99thPercentileLatency(us)," "${log_file}" | awk -F', ' '{print $3}')
                                                p999=$(grep "^\[OVERALL\], 999thPercentileLatency(us)," "${log_file}" | awk -F', ' '{print $3}')
                                                
                                                if [ -n "${throughput}" ]; then
                                                    round_throughputs+=("${throughput}")
                                                    round_p50s+=("${p50}")
                                                    round_p99s+=("${p99}")
                                                    round_p999s+=("${p999}")
                                                fi
                                            fi
                                        done
                                        
                                        # 计算当前配置的平均值并添加到总体统计
                                        if [ ${#round_throughputs[@]} -gt 0 ]; then
                                            avg_throughput=$(calculate_average round_throughputs[@])
                                            avg_p50=$(calculate_average round_p50s[@])
                                            avg_p99=$(calculate_average round_p99s[@])
                                            avg_p999=$(calculate_average round_p999s[@])
                                            
                                            all_throughputs+=("${avg_throughput}")
                                            all_p50s+=("${avg_p50}")
                                            all_p99s+=("${avg_p99}")
                                            all_p999s+=("${avg_p999}")
                                        fi
                                        
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        
        # 计算workload的总体平均值并输出
        if [ ${#all_throughputs[@]} -gt 0 ]; then
            final_throughput=$(calculate_average all_throughputs[@])
            final_p50=$(calculate_average all_p50s[@])
            final_p99=$(calculate_average all_p99s[@])
            final_p999=$(calculate_average all_p999s[@])
            
            # 输出到屏幕和文件
            printf "%-15s %-15s %-20s %-15s %-15s %-15s\n" \
                "${TARGET_SCHEME}" "${workload}" "${final_throughput}" "${final_p50}" "${final_p99}" "${final_p999}" | tee -a "${summary_file}"
        fi
        
    done
    
    echo ""
}


# 辅助函数: 计算数组平均值
function calculate_average {
    local values=("${!1}")
    local sum=0
    local count=${#values[@]}
    
    if [ ${count} -eq 0 ]; then
        echo "0"
        return
    fi
    
    for val in "${values[@]}"; do
        sum=$(echo "${sum} + ${val}" | bc)
    done
    
    echo "scale=2; ${sum} / ${count}" | bc
}

function analyze_timescale_results {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 创建汇总结果目录
    local summary_dir="/home/${UserName}/Results-${CLUSTER_NAME}-${EXP_NAME}-Summary"
    mkdir -p "${summary_dir}"
    local summary_file="${summary_dir}/timescale_stability_${TARGET_SCHEME}.txt"
    
    # 添加表头
    printf "%-15s %-15s %-15s %-20s\n" "Scheme" "Workload" "AverageReadLatency(us)" "Out-of-Range(%)" | tee "${summary_file}"
    printf "%s\n" "--------------------------------------------------------------------" | tee -a "${summary_file}"

    # 遍历所有workload
    for workload in "${ALL_WORKLOADS[@]}"; do
        
        # 存储所有配置的结果
        declare -a all_out_of_range_ratios=()
        declare -a all_base_values=()
        
        # 遍历配置
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for rf in "${REPLICAS[@]}"; do
                for threadsNum in "${THREAD_NUMBER[@]}"; do
                    for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                        for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                            for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                for fieldLength in "${FIELD_LENGTH[@]}"; do
                                    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                                        
                                        # 存储所有round的结果
                                        declare -a round_out_of_range_ratios=()
                                        declare -a round_base_values=()
                                        
                                        # 遍历所有rounds
                                        for round in $(seq 1 ${ROUNDS}); do
                                            # 获取结果目录
                                            resultsDir=$(getResultsDir "${CLUSTER_NAME}" "${TARGET_SCHEME}" "${EXP_NAME}" "RunE" "${workload}" "${dist}" "all" "${threadsNum}" "${schedulingInterval}" "${round}" "false" "${throttleDataRate}" "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" "${consistency}" "${rf}" "${fieldLength}")
                                            
                                            # 查找所有节点目录
                                            local node_dirs=(${resultsDir}/node*)
                                            
                                            if [ ${#node_dirs[@]} -gt 0 ]; then
                                                # 找到coordinator read latency最大的节点
                                                local max_latency=0
                                                local selected_node_dir=""
                                                
                                                for node_dir in "${node_dirs[@]}"; do
                                                    if [ -d "${node_dir}" ]; then
                                                        breakdown_file="${node_dir}/metrics/breakdown.txt"
                                                        
                                                        if [ -f "${breakdown_file}" ]; then
                                                            # 提取 Coordinator read latency: 208.66
                                                            coord_latency=$(grep "CoordinatorReadTime:" "${breakdown_file}" | awk '{print $NF}')
                                                            
                                                            if [ -n "${coord_latency}" ]; then
                                                                # 比较找出最大值
                                                                if (( $(echo "${coord_latency} > ${max_latency}" | bc -l) )); then
                                                                    max_latency="${coord_latency}"
                                                                    selected_node_dir="${node_dir}"
                                                                fi
                                                            fi
                                                        fi
                                                    fi
                                                done
                                                
                                                # 处理选中的节点
                                                if [ -n "${selected_node_dir}" ]; then
                                                    local smallscale_file="${selected_node_dir}/metrics/smallScale.txt"
                                                    
                                                    if [ -f "${smallscale_file}" ]; then
                                                        # 提取所有非零的median值
                                                        declare -a median_values=()
                                                        
                                                        while IFS= read -r line; do
                                                            # 提取Median值: "Mean is: 1899.24, Median is: 1778.05"
                                                            if [[ "$line" =~ Median\ is:\ ([0-9]+\.[0-9]+) ]]; then
                                                                median="${BASH_REMATCH[1]}"
                                                                
                                                                # 跳过0值
                                                                if (( $(echo "$median > 0" | bc -l) )); then
                                                                    median_values+=("$median")
                                                                fi
                                                            fi
                                                        done < "${smallscale_file}"
                                                        
                                                        # 计算base (所有非零median的平均值)
                                                        if [ ${#median_values[@]} -gt 0 ]; then
                                                            local sum=0
                                                            for val in "${median_values[@]}"; do
                                                                sum=$(echo "$sum + $val" | bc -l)
                                                            done
                                                            local base=$(echo "scale=2; $sum / ${#median_values[@]}" | bc -l)
                                                            
                                                            # 计算范围
                                                            local lower_bound=$(echo "scale=2; $base * 0.5" | bc -l)
                                                            local upper_bound=$(echo "scale=2; $base * 2.0" | bc -l)
                                                            
                                                            # 统计不在范围内的数量
                                                            local out_of_range_count=0
                                                            for val in "${median_values[@]}"; do
                                                                if (( $(echo "$val < $lower_bound" | bc -l) )) || (( $(echo "$val > $upper_bound" | bc -l) )); then
                                                                    ((out_of_range_count++))
                                                                fi
                                                            done
                                                            
                                                            # 计算百分比
                                                            local out_of_range_ratio=$(echo "scale=2; $out_of_range_count * 100 / ${#median_values[@]}" | bc -l)
                                                            
                                                            round_base_values+=("$base")
                                                            round_out_of_range_ratios+=("$out_of_range_ratio")
                                                            
                                                            # Debug信息 - 显示选中的节点和延迟
                                                            # echo "Selected node: $(basename ${selected_node_dir}), Max latency: ${max_latency}us, Base: $base, Out-of-range: ${out_of_range_ratio}%"
                                                        fi
                                                        
                                                        unset median_values
                                                    fi
                                                fi
                                            fi
                                        done
                                        
                                        # 计算当前配置的平均值
                                        if [ ${#round_base_values[@]} -gt 0 ]; then
                                            avg_base=$(calculate_average round_base_values[@])
                                            avg_out_of_range=$(calculate_average round_out_of_range_ratios[@])
                                            
                                            all_base_values+=("$avg_base")
                                            all_out_of_range_ratios+=("$avg_out_of_range")
                                        fi
                                        
                                        unset round_base_values round_out_of_range_ratios
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        
        # 计算workload的总体平均值
        if [ ${#all_base_values[@]} -gt 0 ]; then
            final_base=$(calculate_average all_base_values[@])
            final_out_of_range=$(calculate_average all_out_of_range_ratios[@])
            
            # 输出到屏幕和文件
            printf "%-15s %-15s %-15.2f %-20.2f\n" \
                "${TARGET_SCHEME}" "${workload}" "${final_base}" "${final_out_of_range}" | tee -a "${summary_file}"
        fi
        
        unset all_base_values all_out_of_range_ratios
    done
    
    echo ""
}

# 通用的分组分析函数
function analyze_results_by_dimension {
    local dimension_name=$1  # "Consistency" 或 "Distribution"
    local dimension_values=("${!2}")  # 具体的值数组
    local ROUNDS=${3}
    local ALL_WORKLOADS=("${!4}")
    local EXP_NAME=${5}
    local TARGET_SCHEME=${6}
    local REQUEST_DISTRIBUTIONS=("${!7}")
    local REPLICAS=("${!8}")
    local THREAD_NUMBER=("${!9}")
    local SCHEDULING_INTERVAL=("${!10}")
    local THROTLLE_DATA_RATE=("${!11}")
    shift 11
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 创建汇总结果目录
    local summary_dir="/home/${UserName}/Results-${CLUSTER_NAME}-${EXP_NAME}-Summary"
    mkdir -p "${summary_dir}"
    local output_filename="${dimension_name,,}_results_${TARGET_SCHEME}.txt"  # 转小写
    local summary_file="${summary_dir}/${output_filename}"
    
    # 添加表头
    printf "%-15s %-15s %-20s %-20s\n" "Scheme" "${dimension_name}" "Throughput(ops/s)" "P99(us)" | tee "${summary_file}"
    printf "%s\n" "--------------------------------------------------------------------------------" | tee -a "${summary_file}"

    # 遍历所有workload (通常只有一个)
    for workload in "${ALL_WORKLOADS[@]}"; do
        
        # 为每个维度值存储指标
        declare -A all_throughputs_by_dim
        declare -A all_p99s_by_dim
        
        # 初始化数组
        for dim_val in "${dimension_values[@]}"; do
            all_throughputs_by_dim[$dim_val]=""
            all_p99s_by_dim[$dim_val]=""
        done
        
        # 遍历配置
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for rf in "${REPLICAS[@]}"; do
                for threadsNum in "${THREAD_NUMBER[@]}"; do
                    for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                        for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                            for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                for fieldLength in "${FIELD_LENGTH[@]}"; do
                                    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                                        
                                        # 根据维度类型确定当前维度值
                                        local current_dim_value=""
                                        if [ "${dimension_name}" == "Consistency" ]; then
                                            current_dim_value="${consistency}"
                                        elif [ "${dimension_name}" == "Distribution" ]; then
                                            current_dim_value="${dist}"
                                        elif [ "${dimension_name}" == "ValueSize" ]; then
                                            current_dim_value="${fieldLength}"
                                        elif [ "${dimension_name}" == "ClientNumber" ]; then
                                            current_dim_value="${threadsNum}"
                                        else
                                            echo "Unsupported dimension: ${dimension_name}"
                                            return 1
                                        fi
                                        
                                        # 存储当前维度值所有round的数据
                                        declare -a round_throughputs=()
                                        declare -a round_p99s=()
                                        
                                        # 遍历所有rounds
                                        for round in $(seq 1 ${ROUNDS}); do
                                            # 获取结果目录
                                            resultsDir=$(getResultsDir "${CLUSTER_NAME}" "${TARGET_SCHEME}" "${EXP_NAME}" "RunE" "${workload}" "${dist}" "all" "${threadsNum}" "${schedulingInterval}" "${round}" "false" "${throttleDataRate}" "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" "${consistency}" "${rf}" "${fieldLength}")
                                            
                                            # 查找YCSB日志文件
                                            log_file=$(find "${resultsDir}" -maxdepth 1 -name "Run-*proj18*.log" -type f 2>/dev/null | head -n 1)
                                            
                                            if [ -n "${log_file}" ] && [ -f "${log_file}" ]; then
                                                # 提取OVERALL指标
                                                throughput=$(grep "^\[OVERALL\], Throughput(ops/sec)," "${log_file}" | awk -F', ' '{print $3}')
                                                p99=$(grep "^\[OVERALL\], 99thPercentileLatency(us)," "${log_file}" | awk -F', ' '{print $3}')
                                                
                                                # 如果提取到数据,添加到round数组
                                                if [ -n "${throughput}" ] && [ "${throughput}" != "0" ]; then
                                                    round_throughputs+=("${throughput}")
                                                fi
                                                
                                                if [ -n "${p99}" ] && [ "${p99}" != "0" ]; then
                                                    round_p99s+=("${p99}")
                                                fi
                                            fi
                                        done
                                        
                                        # 计算当前配置的平均值
                                        if [ ${#round_throughputs[@]} -gt 0 ]; then
                                            avg_throughput=$(calculate_average round_throughputs[@])
                                            avg_p99=$(calculate_average round_p99s[@])
                                            
                                            # 添加到对应维度值的总体统计
                                            if [ -z "${all_throughputs_by_dim[$current_dim_value]}" ]; then
                                                all_throughputs_by_dim[$current_dim_value]="${avg_throughput}"
                                                all_p99s_by_dim[$current_dim_value]="${avg_p99}"
                                            else
                                                all_throughputs_by_dim[$current_dim_value]="${all_throughputs_by_dim[$current_dim_value]} ${avg_throughput}"
                                                all_p99s_by_dim[$current_dim_value]="${all_p99s_by_dim[$current_dim_value]} ${avg_p99}"
                                            fi
                                        fi
                                        
                                        unset round_throughputs round_p99s
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        
        # 计算并输出每个维度值的最终平均值
        for dim_val in "${dimension_values[@]}"; do
            if [ -n "${all_throughputs_by_dim[$dim_val]}" ]; then
                # 转换为数组并计算总体平均值
                read -ra final_throughput_array <<< "${all_throughputs_by_dim[$dim_val]}"
                read -ra final_p99_array <<< "${all_p99s_by_dim[$dim_val]}"
                
                if [ ${#final_throughput_array[@]} -gt 0 ]; then
                    final_throughput=$(calculate_average final_throughput_array[@])
                    final_p99=$(calculate_average final_p99_array[@])
                    
                    # 输出到屏幕和文件
                    if [ "${dimension_name}" == "ClientNumber" ]; then
                        # double the thread number for saturation analysis
                        Clients
                        dim_val=$((dim_val * ${#Clients[@]}))
                    fi
                    printf "%-15s %-15s %-20.2f %-20.2f\n" \
                        "${TARGET_SCHEME}" "${dim_val}" "${final_throughput}" "${final_p99}" | tee -a "${summary_file}"
                fi
            fi
        done
        
    done
    
    echo ""
}

function analyze_consistency_results {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")
    
    # 调用通用函数,指定维度为 Consistency
    analyze_results_by_dimension "Consistency" CONSISTENCY_LEVEL[@] "${ROUNDS}" ALL_WORKLOADS[@] "${EXP_NAME}" "${TARGET_SCHEME}" REQUEST_DISTRIBUTIONS[@] REPLICAS[@] THREAD_NUMBER[@] SCHEDULING_INTERVAL[@] THROTLLE_DATA_RATE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" COMPACTION_STRATEGY[@] CONSISTENCY_LEVEL[@] FIELD_LENGTH[@]
}

function analyze_distribution_results {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")
    
    # 调用通用函数,指定维度为 Distribution
    analyze_results_by_dimension "Distribution" REQUEST_DISTRIBUTIONS[@] "${ROUNDS}" ALL_WORKLOADS[@] "${EXP_NAME}" "${TARGET_SCHEME}" REQUEST_DISTRIBUTIONS[@] REPLICAS[@] THREAD_NUMBER[@] SCHEDULING_INTERVAL[@] THROTLLE_DATA_RATE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" COMPACTION_STRATEGY[@] CONSISTENCY_LEVEL[@] FIELD_LENGTH[@]
}

function analyze_value_results {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 调用通用函数,指定维度为 ValueSize
    analyze_results_by_dimension "ValueSize" FIELD_LENGTH[@] "${ROUNDS}" ALL_WORKLOADS[@] "${EXP_NAME}" "${TARGET_SCHEME}" REQUEST_DISTRIBUTIONS[@] REPLICAS[@] THREAD_NUMBER[@] SCHEDULING_INTERVAL[@] THROTLLE_DATA_RATE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" COMPACTION_STRATEGY[@] CONSISTENCY_LEVEL[@] FIELD_LENGTH[@]
}

function analyze_saturation_results {
    local ROUNDS=${1}
    local ALL_WORKLOADS=("${!2}")
    local EXP_NAME=${3}
    local TARGET_SCHEME=${4}
    local REQUEST_DISTRIBUTIONS=("${!5}")
    local REPLICAS=("${!6}")
    local THREAD_NUMBER=("${!7}")
    local SCHEDULING_INTERVAL=("${!8}")
    local THROTLLE_DATA_RATE=("${!9}")
    shift 9
    local OPERATION_NUMBER=${1}
    local KV_NUMBER=${2}
    local SSTABLE_SIZE_IN_MB=${3}
    local COMPACTION_STRATEGY=("${!4}")
    local CONSISTENCY_LEVEL=("${!5}")
    local FIELD_LENGTH=("${!6}")

    # 调用通用函数,指定维度为 Client number
    analyze_results_by_dimension "ClientNumber" THREAD_NUMBER[@] "${ROUNDS}" ALL_WORKLOADS[@] "${EXP_NAME}" "${TARGET_SCHEME}" REQUEST_DISTRIBUTIONS[@] REPLICAS[@] THREAD_NUMBER[@] SCHEDULING_INTERVAL[@] THROTLLE_DATA_RATE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" COMPACTION_STRATEGY[@] CONSISTENCY_LEVEL[@] FIELD_LENGTH[@]
}


function runExp {
    
    EXP_NAME=${1}
    TARGET_SCHEME=${2}
    WORKLOAD=${3}
    REQUEST_DISTRIBUTIONS=("${!4}")
    RF=${5}
    THREAD_NUMBER=("${!6}")
    MEMTABLE_SIZE=("${!7}")
    OPERATION_NUMBER=${8}
    KV_NUMBER=${9}
    FIELD_LENGTH=("${!10}")
    KEY_LENGTH=("${!11}")
    KEY_LENGTHMin=${12}
    KEY_LENGTHMax=${13}
    ROUND_NUMBER=${14}
    COMPACTION_LEVEL=("${!15}")
    MOTIVATION=("${!16}")
    MEMORY_LIMIT=${17}
    USE_DIRECTIO=("${!18}")
    REBUILD_SERVER=${19}
    REBUILD_CLIENT=${20}
    LOG_LEVEL=${21}
    BRANCH=${22}
    PURPOSE=${23}
    SCHEDULING_INITIAL_DELAY=${24}
    SCHEDULING_INTERVAL=("${!25}")
    STATES_UPDATE_INTERVAL=${26}
    READ_SENSISTIVITY=${27}
    THROTLLE_DATA_RATE=("${!28}")
    JDK_VERSION=${29}
    SSTABLE_SIZE_IN_MB=${30}
    compaction_strategy=${31}
    CONSISTENCY_LEVEL=("${!32}")

    # test the parameters
    echo "EXP_NAME: ${EXP_NAME}, TARGET_SCHEME: ${TARGET_SCHEME}, Workloads: ${WORKLOAD}, REQUEST_DISTRIBUTIONS: ${REQUEST_DISTRIBUTIONS[@]}, REPLICAS: ${RF}, THREAD_NUMBER: ${THREAD_NUMBER[@]}, MEMTABLE_SIZE: ${MEMTABLE_SIZE[@]}, SSTABLE_SIZE_IN_MB: ${SSTABLE_SIZE_IN_MB}, OPERATION_NUMBER: ${OPERATION_NUMBER}, KV_NUMBER: ${KV_NUMBER}, FIELD_LENGTH: ${FIELD_LENGTH[@]}, KEY_LENGTH: ${KEY_LENGTH[@]}, KEY_LENGTHMin: ${KEY_LENGTHMin}, KEY_LENGTHMax: ${KEY_LENGTHMax}, ROUND_NUMBER: ${ROUND_NUMBER}, COMPACTION_LEVEL: ${COMPACTION_LEVEL[@]}, ENABLE_AUTO_COMPACTION: ${ENABLE_AUTO_COMPACTION}, ENABLE_COMPACTION_CFS: ${ENABLE_COMPACTION_CFS}, MOTIVATION: ${MOTIVATION[@]}, MEMORY_LIMIT: ${MEMORY_LIMIT}, USE_DIRECTIO: ${USE_DIRECTIO[@]}, REBUILD_SERVER: ${REBUILD_SERVER}, REBUILD_CLIENT: ${REBUILD_CLIENT}, LOG_LEVEL: ${LOG_LEVEL}, BRANCH: ${BRANCH}, PURPOSE: ${PURPOSE}, SETTING: ${SETTING}, SCHEDULING_INITIAL_DELAY: ${SCHEDULING_INITIAL_DELAY}, SCHEDULING_INTERVAL: ${SCHEDULING_INTERVAL[@]}, STATES_UPDATE_INTERVAL: ${STATES_UPDATE_INTERVAL}, READ_SENSISTIVITY: ${READ_SENSISTIVITY}, STEP_SIZE: ${STEP_SIZE[@]}, OFFLOAD_THRESHOLD: ${OFFLOAD_THRESHOLD[@]}, RECOVER_THRESHOLD: ${RECOVER_THRESHOLD[@]} readConsistencyLevel: ${CONSISTENCY_LEVEL[@]}, throttleDataRate: ${THROTLLE_DATA_RATE[@]}, JDK_VERSION: ${JDK_VERSION}, compaction_strategy: ${compaction_strategy}"

    ENABLE_HATS="false"
    enableFineSchedule="false"
    enableBackgroundSchedule="false"
    MODEL="${TARGET_SCHEME}"
    if [[ "${TARGET_SCHEME}" == "coarseschedule" ]]; then
        ENABLE_HATS="true"
        TARGET_SCHEME="hats"
    elif [[ "${TARGET_SCHEME}" == "fineschedule" ]]; then
        ENABLE_HATS="true"
        enableFineSchedule="true"
        TARGET_SCHEME="hats"
    elif [[ "${TARGET_SCHEME}" == "hats" ]]; then
        ENABLE_HATS="true"
        enableFineSchedule="true"
        enableBackgroundSchedule="true"
    fi


    # Run experiments
    echo "Start experiment to ${TARGET_SCHEME}"
    perpareJavaEnvironment "${TARGET_SCHEME}" "${JDK_VERSION}"



    if [ "${REBUILD_SERVER}" == "true" ]; then
        echo "Rebuild the server"
        rebuildServer "${BRANCH}"
    fi

    if [ "${REBUILD_CLIENT}" == "true" ]; then
        echo "Rebuild the client"
        rebuildClient "${BRANCH}"
    fi




    for compactionLevel in "${COMPACTION_LEVEL[@]}"; do
        # for rf in "${REPLICAS[@]}"; do
            # Copy the data set to each node and startup the process from th dataset
            # if [ "$BACKUP_MODE" != "local" ]; then
            #     copyDatasetToNodes "${EXP_NAME}" "${scheme}" "${KV_NUMBER}" "${KEY_LENGTH}" "${FIELD_LENGTH}" "${rf}" "${compactionLevel}" "${PURPOSE}"
            #     sleep 600
            # fi
            # for round in $(seq 1 $ROUND_NUMBER); do
        for dist in "${REQUEST_DISTRIBUTIONS[@]}"; do
            for threadsNum in "${THREAD_NUMBER[@]}"; do
                for memtableSize in "${MEMTABLE_SIZE[@]}"; do
                    for directIO in "${USE_DIRECTIO[@]}"; do
                        for motivation in "${MOTIVATION[@]}"; do
                            for schedulingInterval in "${SCHEDULING_INTERVAL[@]}"; do
                                for throttleDataRate in "${THROTLLE_DATA_RATE[@]}"; do
                                    for consistency in "${CONSISTENCY_LEVEL[@]}"; do
                                        for keyLength in "${KEY_LENGTH[@]}"; do
                                            for fieldLength in "${FIELD_LENGTH[@]}"; do
                                                if [ "${compactionLevel}" == "zero" ]; then
                                                    ENABLE_AUTO_COMPACTION="false"
                                                    ENABLE_COMPACTION_CFS=""
                                                elif [ "${compactionLevel}" == "one" ]; then
                                                    ENABLE_AUTO_COMPACTION="true"
                                                    ENABLE_COMPACTION_CFS="usertable0"
                                                elif [ "${compactionLevel}" == "all" ]; then
                                                    ENABLE_AUTO_COMPACTION="true"
                                                    ENABLE_COMPACTION_CFS="usertable0 usertable1 usertable2"
                                                fi
                                                echo "RunDB: Start round ${ROUND_NUMBER}, the threads number is ${threadsNum}, sstable size is ${SSTABLE_SIZE_IN_MB}, memtable size is ${memtableSize}, rf is ${RF}, workload is ${WORKLOAD}, request distribution is ${dist} and compaction level is ${compactionLevel}, enableAutoCompaction is ${ENABLE_AUTO_COMPACTION}, throttleDataRate is ${throttleDataRate} MB/s, the read consistency level is ${consistency}"

                                                SETTING=$(getSettingName ${motivation} ${compactionLevel})

                                                # init the configuration file, set all nodes as the seeds to support fast startup
                                                initConf "false"
                                                # Trim SSD before the evaluation
                                                trimSSD
                                                # if [ "$TARGET_SCHEME" != "depart-5.0" ]; then
                                                # startup from preload dataset
                                                if [ "${WORKLOAD}" == "workloadc" ]; then
                                                    echo "Start from current data"
                                                    restartCassandra ${memtableSize} ${motivation} ${REBUILD_SERVER} "${directIO}" "${LOG_LEVEL}" "${BRANCH}" "${SCHEDULING_INITIAL_DELAY}" "${schedulingInterval}" "${STATES_UPDATE_INTERVAL}" "${READ_SENSISTIVITY}" ${ENABLE_HATS} ${throttleDataRate} ${enableFineSchedule} ${enableBackgroundSchedule}
                                                # modify the seeds as the specific nodes, and reload the configuration file
                                                else
                                                    echo "Start from backup"
                                                    startFromBackup "LoadDB" $TARGET_SCHEME ${KV_NUMBER} ${keyLength} ${fieldLength} ${RF} ${memtableSize} ${motivation} ${REBUILD_SERVER} "${directIO}" "${LOG_LEVEL}" "${BRANCH}" "${SCHEDULING_INITIAL_DELAY}" "${schedulingInterval}" "${STATES_UPDATE_INTERVAL}" "${READ_SENSISTIVITY}" ${ENABLE_HATS} ${throttleDataRate} ${SSTABLE_SIZE_IN_MB} ${compaction_strategy} ${enableFineSchedule} ${enableBackgroundSchedule}
                                                fi
                                                # fi
                                                initConf "true"
                                                reloadSeeds ${TARGET_SCHEME}

                                                opsNum=${OPERATION_NUMBER}
                                                if [ "${WORKLOAD}" == "workloade" ]; then
                                                    opsNum=$((opsNum / 100))
                                                fi
                                                requestDist=${dist}
                                                # if [ "${WORKLOAD}" == "workloadd" ]; then
                                                #     requestDist="latest"
                                                # fi
                                                enableStartProbe="false"
                                                if [ "${EXP_NAME}" == "Exp5-timescale" ]; then
                                                    enableStartProbe="true"
                                                fi
                                                run ${TARGET_SCHEME} ${requestDist} ${WORKLOAD} ${threadsNum} ${KV_NUMBER} ${opsNum} ${keyLength} ${fieldLength} ${ENABLE_AUTO_COMPACTION} "${ENABLE_COMPACTION_CFS}" "${MEMORY_LIMIT}" "${LOG_LEVEL}" "${ENABLE_HATS}" "${consistency}" "${enableStartProbe}"

                                                # Set the seed nodes as all the nodes, and reload the configuration file
                                                initConf "false"
                                                reloadSeeds ${TARGET_SCHEME}


                                                # Collect load results
                                                resultsDir=$(getResultsDir ${CLUSTER_NAME} ${MODEL} ${EXP_NAME} ${SETTING} ${workload} ${requestDist} ${compactionLevel} ${threadsNum} ${schedulingInterval} ${ROUND_NUMBER} ${ENABLE_HATS} ${throttleDataRate} ${OPERATION_NUMBER} ${KV_NUMBER} ${SSTABLE_SIZE_IN_MB} ${compaction_strategy} ${consistency} ${RF} ${fieldLength}) 

                                                # echo "Collect results to ${resultsDir}"
                                                collectResults ${resultsDir}
                                            done
                                        done
                                    done
                                done
                            done
                        done
                    done
                done
            done
        done
        # done
    done
}

function getModel {
    local scheme=${1}
    if [[ "${scheme}" == "coarseschedule" ]] || [[ "${scheme}" == "fineschedule" ]] || [[ "${scheme}" == "hats" ]]; then
        echo "hats"
    else
        echo "${scheme}"
    fi
}

function runPureReadExp {
    
    EXP_NAME=${1}
    TARGET_SCHEME=${2}
    WORKLOAD=${3}
    REQUEST_DISTRIBUTIONS=("${!4}")
    REPLICAS=("${!5}")
    THREAD_NUMBER=("${!6}")
    MEMTABLE_SIZE=("${!7}")
    OPERATION_NUMBER=${8}
    KV_NUMBER=${9}
    FIELD_LENGTH=("${!10}")
    KEY_LENGTH=("${!11}")
    KEY_LENGTHMin=${12}
    KEY_LENGTHMax=${13}
    ROUND_NUMBER=${14}
    COMPACTION_LEVEL=("${!15}")
    MOTIVATION=("${!16}")
    MEMORY_LIMIT=${17}
    USE_DIRECTIO=("${!18}")
    REBUILD_SERVER=${19}
    REBUILD_CLIENT=${20}
    LOG_LEVEL=${21}
    BRANCH=${22}
    PURPOSE=${23}
    SCHEDULING_INITIAL_DELAY=${24}
    SCHEDULING_INTERVAL=("${!25}")
    STATES_UPDATE_INTERVAL=${26}
    READ_SENSISTIVITY=${27}
    THROTLLE_DATA_RATE=("${!28}")
    JDK_VERSION=${29}
    SSTABLE_SIZE_IN_MB=${30}
    COMPACTION_STRATEGY=("${!31}")
    CONSISTENCY_LEVEL=("${!32}")



    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
        for rf in "${REPLICAS[@]}"; do
            loadDataset "${EXP_NAME}" $(getModel "$TARGET_SCHEME") "${KV_NUMBER}" "${KEY_LENGTH}" "${FIELD_LENGTH}" "${rf}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}"
            runExp "${EXP_NAME}" "$TARGET_SCHEME" $WORKLOAD REQUEST_DISTRIBUTIONS[@] ${rf} THREAD_NUMBER[@] MEMTABLE_SIZE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" FIELD_LENGTH[@] KEY_LENGTH[@] "${KEY_LENGTHMin}" "${KEY_LENGTHMax}" "${ROUND_NUMBER}" COMPACTION_LEVEL[@]  MOTIVATION[@] "${MEMORY_LIMIT}" USE_DIRECTIO[@] "${REBUILD_SERVER}" "${REBUILD_CLIENT}" "${LOG_LEVEL}" "${BRANCH}" "${PURPOSE}" "${SCHEDULING_INITIAL_DELAY}" SCHEDULING_INTERVAL[@] "${STATES_UPDATE_INTERVAL}" "${READ_SENSISTIVITY}" THROTLLE_DATA_RATE[@] "${JDK_VERSION}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" CONSISTENCY_LEVEL[@]
            cleanup $(getModel "$TARGET_SCHEME")
        done
    done


}

function runMixedReadWriteExp {

    EXP_NAME=${1}
    TARGET_SCHEME=${2}
    WORKLOAD=${3}
    REQUEST_DISTRIBUTIONS=("${!4}")
    REPLICAS=("${!5}")
    THREAD_NUMBER=("${!6}")
    MEMTABLE_SIZE=("${!7}")
    OPERATION_NUMBER=${8}
    KV_NUMBER=${9}
    FIELD_LENGTH=("${!10}")
    KEY_LENGTH=("${!11}")
    KEY_LENGTHMin=${12}
    KEY_LENGTHMax=${13}
    ROUND_NUMBER=${14}
    COMPACTION_LEVEL=("${!15}")
    MOTIVATION=("${!16}")
    MEMORY_LIMIT=${17}
    USE_DIRECTIO=("${!18}")
    REBUILD_SERVER=${19}
    REBUILD_CLIENT=${20}
    LOG_LEVEL=${21}
    BRANCH=${22}
    PURPOSE=${23}
    SCHEDULING_INITIAL_DELAY=${24}
    SCHEDULING_INTERVAL=("${!25}")
    STATES_UPDATE_INTERVAL=${26}
    READ_SENSISTIVITY=${27}
    THROTLLE_DATA_RATE=("${!28}")
    JDK_VERSION=${29}
    SSTABLE_SIZE_IN_MB=${30}
    COMPACTION_STRATEGY=("${!31}")
    CONSISTENCY_LEVEL=("${!32}")
    


    for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
        for rf in "${REPLICAS[@]}"; do
            runExp "${EXP_NAME}" "$TARGET_SCHEME" $WORKLOAD REQUEST_DISTRIBUTIONS[@] ${rf} THREAD_NUMBER[@] MEMTABLE_SIZE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" FIELD_LENGTH[@] KEY_LENGTH[@] "${KEY_LENGTHMin}" "${KEY_LENGTHMax}" "${ROUND_NUMBER}" COMPACTION_LEVEL[@]  MOTIVATION[@] "${MEMORY_LIMIT}" USE_DIRECTIO[@] "${REBUILD_SERVER}" "${REBUILD_CLIENT}" "${LOG_LEVEL}" "${BRANCH}" "${PURPOSE}" "${SCHEDULING_INITIAL_DELAY}" SCHEDULING_INTERVAL[@] "${STATES_UPDATE_INTERVAL}" "${READ_SENSISTIVITY}" THROTLLE_DATA_RATE[@] "${JDK_VERSION}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" CONSISTENCY_LEVEL[@]
            cleanup $(getModel "$TARGET_SCHEME")
        done
    done

}