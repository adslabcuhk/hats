#!/bin/bash
. /etc/profile

function manageCache {

    sudoPasswd=$1
    memoryLimit=$2
    
    # clean cache
    # nohup bash -c 'while true; do echo "$sudoPasswd" | sudo -S sh -c "echo 1 > /proc/sys/vm/drop_caches"; sleep 10; done' >/dev/null 2>&1 &

    

    # set memory high
    CASSANDRA_PID=$(ps aux | grep CassandraDaemon | grep -v grep | awk '{print $2}')
    echo $sudoPasswd | sudo -S  sh -c "mkdir -p /sys/fs/cgroup/cassandra"
    echo $sudoPasswd | sudo -S  sh -c "echo $CASSANDRA_PID > /sys/fs/cgroup/cassandra/cgroup.procs"
    echo $sudoPasswd | sudo -S  sh -c "echo $memoryLimit > /sys/fs/cgroup/cassandra/memory.high"
}

manageCache "$1" "$2"