#!/bin/bash
. /etc/profile
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# source "${SCRIPT_DIR}/../settings.sh"

function captureCPU_RAM {
    expName=$1
    stage=$2
    resultDir=$3
    SimpleBase=5

    CASSANDRA_PID=$(ps aux | grep CassandraDaemon | grep -v grep | awk '{print $2}')
    echo "Cassandra PID: $CASSANDRA_PID"

    OUTPUT_MEM="${resultDir}/${expName}_${stage}_memory_usage.txt"
    echo "Memory overhead for Cassandra PID: $CASSANDRA_PID, Exp = ${expName}, stage = $stage" >>"$OUTPUT_MEM"

    while true; do
        # If Cassandra is running, get its memory usage
        if [[ ! -z "$CASSANDRA_PID" ]]; then
            MEM_USAGE=$(ps -o rss= -p "$CASSANDRA_PID")
            echo "$(date): Cassandra PID $CASSANDRA_PID is using $MEM_USAGE KiB" >>"$OUTPUT_MEM"
        else
            echo "$(date): Cassandra is not running" >>"$OUTPUT_MEM"
            exit
        fi
        # Wait for $SimpleBase seconds before the next check
        sleep $SimpleBase
    done
}

captureCPU_RAM "$1" "$2" "$3"
