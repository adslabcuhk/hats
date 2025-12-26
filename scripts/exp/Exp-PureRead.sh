#!/bin/bash


. /etc/profile

# Workload Settings
EXP_NAME="Exp-PureRead"
WORKLOADS=("workloadc")
REQUEST_DISTRIBUTIONS=("zipfian") # zipfian uniform
OPERATION_NUMBER=25000000
KV_NUMBER=100000000
FIELD_LENGTH=(1000)
KEY_LENGTH=(24)
KEY_LENGTHMin=24
KEY_LENGTHMax=24
REPLICAS=(3)
THREAD_NUMBER=(50)
MEMTABLE_SIZE=(2048)
MOTIVATION=("false") # true is only forward the read request to the primary lsm-tree
MEMORY_LIMIT="12G"
USE_DIRECTIO=("false") # enable direct io for read path or not
PURPOSE="ReadAmplification" # To prove ReadAmplification, CompactionOverhead, we select different dataset
READ_SENSISTIVITY=0.9
BRANCH="main"
LOG_LEVEL="info"
SSTABLE_SIZE_IN_MB=160
COMPACTION_STRATEGY=("LCS")
CONSISTENCY_LEVEL=("ONE")


# Debug Settings
REBUILD_SERVER="false"
REBUILD_CLIENT="false"

# Server settings
ROUNDS=1
COMPACTION_LEVEL=("all") # zero one all

# Hats
SCHEDULING_INITIAL_DELAY=600 # seconds
SCHEDULING_INTERVAL=(60) # seconds
STATES_UPDATE_INTERVAL=10 # seconds
THROTLLE_DATA_RATE=(90) # MB/s

JDK_VERSION="17"

SCHEMES=("mlsm")


function exportEnv {
    
    scheme=$1
    
    export BACKUP_MODE="local"
    export SCHEME=$scheme # hats or depart
    export CLUSTER_NAME="1x"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    source "${SCRIPT_DIR}/../common.sh"
}

for ROUND_NUMBER in $(seq 1 $ROUNDS); do
    for WORKLOAD in "${WORKLOADS[@]}"; do
        for scheme in "${SCHEMES[@]}"; do
            for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do        
                for rf in "${REPLICAS[@]}"; do
                    exportEnv $scheme
                    loadDataset "${EXP_NAME}" "$scheme" "${KV_NUMBER}" "${KEY_LENGTH}" "${FIELD_LENGTH}" ${rf} "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}"
                    runExp "${EXP_NAME}" "$scheme" "${WORKLOAD}" REQUEST_DISTRIBUTIONS[@] ${rf} THREAD_NUMBER[@] MEMTABLE_SIZE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" FIELD_LENGTH[@] KEY_LENGTH[@] "${KEY_LENGTHMin}" "${KEY_LENGTHMax}" "${ROUND_NUMBER}" COMPACTION_LEVEL[@]  MOTIVATION[@] "${MEMORY_LIMIT}" USE_DIRECTIO[@] "${REBUILD_SERVER}" "${REBUILD_CLIENT}" "${LOG_LEVEL}" "${BRANCH}" "${PURPOSE}" "${SCHEDULING_INITIAL_DELAY}" SCHEDULING_INTERVAL[@] "${STATES_UPDATE_INTERVAL}" "${READ_SENSISTIVITY}" THROTLLE_DATA_RATE[@] "${JDK_VERSION}" "${SSTABLE_SIZE_IN_MB}" "${compaction_strategy}" CONSISTENCY_LEVEL[@]
                    cleanup $scheme
                done
            done
        done
    done
done
