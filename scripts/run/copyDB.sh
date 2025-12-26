#!/bin/bash
. /etc/profile
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# source "${SCRIPT_DIR}/../common.sh"

func() {

    echo "Backup DB data from $2 to $3"
    projectBaseDir=$1
    sourceDataDir=$2
    targetDataDir=$3
    configureFilePath=$4

    rm -rf "${targetDataDir}"
    if [ ! -d "${targetDataDir}" ]; then
        mkdir -p "${targetDataDir}"
    fi

    if [ ! -d "${sourceDataDir}" ]; then
        echo "Target ${sourceDataDir} does not exist"
        exit
    fi

    cd ${projectBaseDir} || exit


    bin/nodetool drain

    sleep 10

    pkill -9 -f CassandraDaemon || true


    cp -r "${sourceDataDir}" "${targetDataDir}"
    cp -r "${configureFilePath}" "${targetDataDir}"
}

func "$1" "$2" "$3" "$4"
