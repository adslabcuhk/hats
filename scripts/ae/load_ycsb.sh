#!/bin/bash


. /etc/profile

SCHEMES=("mlsm" "depart-5.0")
CLUSTER_NAMES=("1x")
REPLICAS=(3)
SSTABLE_SIZE_IN_MB=160
KV_NUMBER=100000000
FIELD_LENGTH=(512 2048)
KEY_LENGTH=24
REBUILD_SERVER="false"
WAIT_TIME=3600
COMPACTION_STRATEGY=("LCS")

JDK_VERSION="17"
LOG_LEVEL="error"
BRANCH="main"


function exportEnv {
    local scheme=$1
    local cluster_name=$2

    export BACKUP_MODE="local"
    export SCHEME=$scheme # hats or depart
    export CLUSTER_NAME="$cluster_name"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    source "${SCRIPT_DIR}/../common.sh"
    Clients=("proj18")
    ClientsIP=("192.168.50.18")
    initConf "false"
}


function main {

    for cluster_name in "${CLUSTER_NAMES[@]}"; do
        for scheme in "${SCHEMES[@]}"; do
            echo "Load data for ${scheme}"
            exportEnv $scheme $cluster_name
            perpareJavaEnvironment "${scheme}" "${JDK_VERSION}"
            
            if [ "${REBUILD_SERVER}" == "true" ]; then
                echo "Rebuild the server"
                rebuildServer "${BRANCH}" "${scheme}"
            fi

            if [ "${cluster_name}" == "1x" ]; then
                KV_NUMBER=100000000
            elif [ "${cluster_name}" == "2x" ]; then
                KV_NUMBER=150000000
            elif [ "${cluster_name}" == "3x" ]; then
                KV_NUMBER=200000000
            fi
            
            for rf in "${REPLICAS[@]}"; do
                for compaction_strategy in "${COMPACTION_STRATEGY[@]}"; do
                    for value_size in "${FIELD_LENGTH[@]}"; do
                        # Load data
                        load $scheme 10 "${SSTABLE_SIZE_IN_MB}" 2048 "${rf}" "workload_template" ${KV_NUMBER} ${value_size} ${KEY_LENGTH} ${compaction_strategy} ${LOG_LEVEL} ${BRANCH}
                        # Wait for flush or compaction ready
                        flush "LoadDB" $scheme $WAIT_TIME
                        # Backup the DB and the logs
                        backup "LoadDB" $scheme ${KV_NUMBER} ${KEY_LENGTH} ${value_size} ${rf} "${SSTABLE_SIZE_IN_MB}" ${compaction_strategy}
                        cleanup "$scheme"
                    done
                done
            done
        done
    done
}

main
