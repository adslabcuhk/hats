#!/bin/bash
. /etc/profile
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# source "${SCRIPT_DIR}/../settings.sh"

function statsCPU_Disk_Network_DB {
    expName=$1
    workload=$2
    stage=$3
    resultDir=$4
    pathToCodeBase=$5
    diskDevice=$6
    INTERFACE=$7
    targetScheme=$8

    hostname=$(hostname)

    if [[ $hostname == *"node11"* ]] || [[ $hostname == *"node15"* ]] || [[ $hostname == *"node20"* ]]; then
        INTERFACE="eth1"
    fi

    CASSANDRA_PID=$(ps aux | grep CassandraDaemon | grep -v grep | awk '{print $2}')
    echo "expName is $expName, workload is $workload, stage is $stage, resultDir is $resultDir, pathToCodeBase is $pathToCodeBase, diskDevice is $diskDevice, INTERFACE is $INTERFACE, targetScheme is $targetScheme, Cassandra PID: $CASSANDRA_PID"

    ## CPU
    CPU_OUTPUT_FILE="${resultDir}/${stage}_cpu_summary.txt"
    SYSTEM_TICKS=$(getconf CLK_TCK)

    # Get the process execution time in seconds
    SYS_UPTIME=$(cat /proc/uptime | awk '{print $1}')
    PROC_STARTTIME_JIFFIES=$(cat /proc/$CASSANDRA_PID/stat | awk '{print $22}')
    PROC_STARTTIME_SECONDS=$(echo "$PROC_STARTTIME_JIFFIES / $SYS_UPTIME" | bc -l)
    PROC_UPTIME_SECONDS=$(echo "$SYS_UPTIME - $PROC_STARTTIME_SECONDS" | bc -l)

    # Get the process CPU time in seconds
    USER_TIME_SECONDS=$(echo "scale=2; $(cat /proc/$CASSANDRA_PID/stat | awk '{print $14}') / $SYSTEM_TICKS" | bc)
    SYS_TIME_SECONDS=$(echo "scale=2; $(cat /proc/$CASSANDRA_PID/stat | awk '{print $15}') / $SYSTEM_TICKS" | bc)
    echo "Summary for process: $CASSANDRA_PID at stage $stage" >$CPU_OUTPUT_FILE
    echo "Process uptime (seconds): $PROC_UPTIME_SECONDS" >>$CPU_OUTPUT_FILE
    echo "User time (seconds): $USER_TIME_SECONDS" >>$CPU_OUTPUT_FILE
    echo "System time (seconds): $SYS_TIME_SECONDS" >>$CPU_OUTPUT_FILE



    ## Network I/O
    # Network interface (change this to your interface, e.g., wlan0, ens33, etc.)
    # INTERFACE=${networkInterface}

    # File to store the results
    NET_OUTPUT_FILE="${resultDir}/${stage}_network_summary.txt"

    # Extract the received (RX) and transmitted (TX) bytes for the specified interface
    RX_BYTES=$(cat /proc/$CASSANDRA_PID/net/dev | grep $INTERFACE | awk '{print $2}')
    TX_BYTES=$(cat /proc/$CASSANDRA_PID/net/dev | grep $INTERFACE | awk '{print $10}')

    # Write the results to the file
    echo "Summary for interface: $INTERFACE at stage $stage" >$NET_OUTPUT_FILE
    echo "Bytes received: $RX_BYTES" >>$NET_OUTPUT_FILE
    echo "Bytes sent: $TX_BYTES" >>$NET_OUTPUT_FILE



    ## Disk I/O

    # File to store the results
    IO_OUTPUT_FILE="${resultDir}/${stage}_disk_io_total.txt"

    rchar=$(grep -Po '(?<=rchar: )\d+' "/proc/$CASSANDRA_PID/io")
    wchar=$(grep -Po '(?<=wchar: )\d+' "/proc/$CASSANDRA_PID/io")
    read_bytes=$(grep -Po '^read_bytes: \K\d+' "/proc/$CASSANDRA_PID/io")
    write_bytes=$(grep -Po '^write_bytes: \K\d+' "/proc/$CASSANDRA_PID/io")

    rchar_kb=$(echo "$rchar / 1024" | bc)
    wchar_kb=$(echo "$wchar / 1024" | bc)
    read_bytes_kb=$(echo "$read_bytes / 1024" | bc)
    write_bytes_kb=$(echo "$write_bytes / 1024" | bc)

    # Write the results to the file
    echo "Summary for disk io: PID number is $CASSANDRA_PID" >$IO_OUTPUT_FILE
    echo "Disk KiB read: $read_bytes_kb" >>$IO_OUTPUT_FILE
    echo "Disk KiB written: $write_bytes_kb" >>$IO_OUTPUT_FILE
    echo "Total KiB read: $rchar_kb" >>$IO_OUTPUT_FILE
    echo "Total KiB written: $wchar_kb" >>$IO_OUTPUT_FILE

    # File to store the results
    DB_OUTPUT_FILE="${resultDir}/${stage}_db_stats.txt"
    echo "Record DB status at stage ${stage}" >"$DB_OUTPUT_FILE"
    # Write the results to the file
    cd ${pathToCodeBase} || exit

    if [ "$targetScheme" == "mlsm" ] || [ "$targetScheme" == "hats" ] || [ "$targetScheme" == "c3" ]; then
        bin/nodetool tablestats ycsb.usertable0 | grep "Local" | grep "count" >>"$DB_OUTPUT_FILE"
        bin/nodetool tpstats >>"$DB_OUTPUT_FILE"
        bin/nodetool tablehistograms ycsb.usertable0 >>"${resultDir}/${stage}_db_latency_breakdown_usertable0.txt"
        bin/nodetool tablestats ycsb.usertable1 | grep "Local" | grep "count" >>"$DB_OUTPUT_FILE"
        bin/nodetool tpstats >>"$DB_OUTPUT_FILE"
        bin/nodetool tablehistograms ycsb.usertable1 >>"${resultDir}/${stage}_db_latency_breakdown_usertable1.txt"
        bin/nodetool tablestats ycsb.usertable2 | grep "Local" | grep "count" >>"$DB_OUTPUT_FILE"
        bin/nodetool tpstats >>"$DB_OUTPUT_FILE"
        bin/nodetool tablehistograms ycsb.usertable2 >>"${resultDir}/${stage}_db_latency_breakdown_usertable2.txt"
    else
        bin/nodetool tablestats ycsb.usertable | grep "Local" | grep "count" >>"$DB_OUTPUT_FILE"
        bin/nodetool tpstats >>"$DB_OUTPUT_FILE"
        bin/nodetool tablehistograms ycsb.usertable >>"${resultDir}/${stage}_db_latency_breakdown_usertable.txt"
    fi


    echo "Total storage usage:" >>"$DB_OUTPUT_FILE"
    du -s --bytes ${pathToCodeBase}/data/ | awk '{print $1}' >>"$DB_OUTPUT_FILE"
    echo "LSM-tree:" >>"$DB_OUTPUT_FILE"
    du -s --bytes ${pathToCodeBase}/data/data/ | awk '{print $1}' >>"$DB_OUTPUT_FILE"

}

statsCPU_Disk_Network_DB "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
