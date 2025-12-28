# Obtain the results for Exp#3 (Facebook's production workload performance)
. /etc/profile
# Workload Settings
EXP_NAME="exp3"
PURE_READ_WORKLOADS=()
MIXED_READ_WRITE_WORKLOADS=("workload_mixgraph")
REQUEST_DISTRIBUTIONS=("mixgraph") # zipfian uniform
OPERATION_NUMBER=500000000
KV_NUMBER=50000000
FIELD_LENGTH=(2000)
KEY_LENGTH=(48)
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
LOG_LEVEL="error"
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
SCHEDULING_INITIAL_DELAY=120 # seconds
SCHEDULING_INTERVAL=(60) # seconds
STATES_UPDATE_INTERVAL=10 # seconds
THROTLLE_DATA_RATE=(90) # MB/s

JDK_VERSION="17"

SCHEMES=("hats" "depart-5.0" "c3" "mlsm")

function exportEnv {
    scheme=$1
    export BACKUP_MODE="local"
    export SCHEME=$scheme # hats or depart
    export CLUSTER_NAME="1x"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    source "${SCRIPT_DIR}/../common.sh"
}

# time the experiments
SECONDS=0
for ROUND_NUMBER in $(seq 1 $ROUNDS); do
    for WORKLOAD in "${MIXED_READ_WRITE_WORKLOADS[@]}"; do
        for scheme in "${SCHEMES[@]}"; do
            exportEnv "${scheme}"
            
            runMixedReadWriteExp "${EXP_NAME}" "${scheme}" "${WORKLOAD}" REQUEST_DISTRIBUTIONS[@] REPLICAS[@] THREAD_NUMBER[@] MEMTABLE_SIZE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" FIELD_LENGTH[@] KEY_LENGTH[@] "${KEY_LENGTHMin}" "${KEY_LENGTHMax}" "${ROUND_NUMBER}" COMPACTION_LEVEL[@]  MOTIVATION[@] "${MEMORY_LIMIT}" USE_DIRECTIO[@] "${REBUILD_SERVER}" "${REBUILD_CLIENT}" "${LOG_LEVEL}" "${BRANCH}" "${PURPOSE}" "${SCHEDULING_INITIAL_DELAY}" SCHEDULING_INTERVAL[@] "${STATES_UPDATE_INTERVAL}" "${READ_SENSISTIVITY}" THROTLLE_DATA_RATE[@] "${JDK_VERSION}" "${SSTABLE_SIZE_IN_MB}" COMPACTION_STRATEGY[@] CONSISTENCY_LEVEL[@]

        done
    done
done
echo "Run Exp#3 took $SECONDS seconds." >> "${ALL_RESULTS}"

mkdir -p ~/Results
echo "" > ~/Results/${EXP_NAME}_summary.txt
{
    echo "##############################################################"
    echo "#     Exp#3 (Facebook's production workload performance)     #"
    echo "##############################################################"
    for scheme in "${SCHEMES[@]}"; do
        exportEnv "${scheme}"
        analyze_facebook_results "${ROUNDS}" ALL_WORKLOADS[@] "${EXP_NAME}" "${scheme}" REQUEST_DISTRIBUTIONS[@] REPLICAS[@] THREAD_NUMBER[@] SCHEDULING_INTERVAL[@] THROTLLE_DATA_RATE[@] "${OPERATION_NUMBER}" "${KV_NUMBER}" "${SSTABLE_SIZE_IN_MB}" COMPACTION_STRATEGY[@] CONSISTENCY_LEVEL[@] FIELD_LENGTH[@]
    done
} | tee ~/Results/${EXP_NAME}_summary.txt
