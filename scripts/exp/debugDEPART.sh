#!/bin/bash


. /etc/profile

SCHEMES=("depart-5.0")
REPLICAS=(3)
SSTABLE_SIZE_IN_MB=16
KV_NUMBER=1000000
OPERATION_NUMBER=2000000
FIELD_LENGTH=1000
KEY_LENGTH=24
REBUILD_SERVER="true"
WAIT_TIME=600


ENABLE_AUTO_COMPACTION="true"
ENABLE_COMPACTION_CFS="usertable"
MEMORY_LIMIT="12G"
LOG_LEVEL="debug"
shuffleReplicas="true"

JDK_VERSION="17"

function exportEnv {
    
    scheme=$1

    export BACKUP_MODE="local"
    export SCHEME=$scheme # hats or depart
    export CLUSTER_NAME="1x"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    source "${SCRIPT_DIR}/../common.sh"
}


function main {

    for scheme in "${SCHEMES[@]}"; do
        echo "Load data for ${scheme}"
        exportEnv $scheme
        perpareJavaEnvironment "${scheme}" "${JDK_VERSION}"
        
        if [ "${REBUILD_SERVER}" == "true" ]; then
            echo "Rebuild the server"
            rebuildServer "${BRANCH}" "${scheme}"
        fi

        for rf in "${REPLICAS[@]}"; do
            # Load data
            load $scheme 16 "${SSTABLE_SIZE_IN_MB}" 2048 "${rf}" "workload_template" ${KV_NUMBER} ${FIELD_LENGTH} ${KEY_LENGTH}
            # Wait for flush or compaction ready
            flush "LoadDB" $scheme $WAIT_TIME
            # Backup the DB and the logs
            # backup "LoadDB" $scheme ${KV_NUMBER} ${KEY_LENGTH} ${FIELD_LENGTH} ${rf}

            # Run the workload
            run ${scheme} "zipfian" "workloadc" 4 ${KV_NUMBER} ${OPERATION_NUMBER} ${KEY_LENGTH} ${FIELD_LENGTH} ${ENABLE_AUTO_COMPACTION} "${ENABLE_COMPACTION_CFS}" "${MEMORY_LIMIT}" "${LOG_LEVEL}" "${shuffleReplicas}"
        done
    done
}

main
