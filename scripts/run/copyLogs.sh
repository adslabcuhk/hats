#!/bin/bash
. /etc/profile
func() {

    recordcount=$1
    operationcount=$2
    threads=$3
    workload=$4
    expName=$5
    keyspace=$6
    resultDir=$7
    logDir=$8
    


    cp -r ${resultDir} ~/Results
    cp -r ${logDir} ~/Results   
}

func "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
