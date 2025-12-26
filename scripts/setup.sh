#!/bin/bash

. /etc/profile
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

function updateScript {
    # Update the server
    cluster_name=$1
    export CLUSTER_NAME=$cluster_name
    echo "Update the server on ${CLUSTER_NAME}"
    source ${SCRIPT_DIR}/settings.sh
    for node in "${AllNodes[@]}"; do
        echo "Update the server on ${node}"
        ssh "${node}" "cd ${PathToScripts} && git pull"
    done

}

function updateCode {
    # Update the server
    cluster_name=$1
    export CLUSTER_NAME=$cluster_name    
    source ${SCRIPT_DIR}/settings.sh
    for node in "${ServersIP[@]}"; do
        echo "Update the server on ${node}"
        ssh "${node}" "cd ${PathToServer} && git pull && ant clean && ant"
    done
}

function main {
    case $1 in
        "updateScript")
            updateScript $2
            ;;
        "updateCode")
            updateCode $2
            ;;
        *)
            echo "Invalid command $1"
            ;;
    esac
}


main "$1" "$2"

exit