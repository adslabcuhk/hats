#!/bin/bash

# CLUSTER_NAME=""
# BACKUP_MODE="" # local remote
# SCHEME="" # depart or hats
PROJECT_NAME="hats"
HOME_PATH=""
# echo "Load the settings.sh, CLUSTER_NAME is ${CLUSTER_NAME}, BACKUP_MODE is ${BACKUP_MODE}, SCHEME is ${SCHEME}"
if [[ "$CLUSTER_NAME" == "" ]]; then
    echo "Please specify the CLUSTER_NAME"
    exit 1
elif [[ "$CLUSTER_NAME" == "1x" ]]; then
    # Servers=("node11" "node12" "node13"  "node15" "node16" "node17" "node18" "node19" "node20" "node21")
    # ServersIP=("192.168.10.21" "192.168.10.22" "192.168.10.23"  "192.168.10.25" "192.168.10.26" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31")
    # Servers=("node11" "node12" "node13"  "node15" "node16" "node18" "node19" "node20" "node21" "node22")
    # ServersIP=("192.168.10.21" "192.168.10.22" "192.168.10.23"  "192.168.10.25" "192.168.10.26" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32")
    # Servers=("node11" "node12" "node13"  "node15" "node17" "node18" "node19" "node20" "node21" "node22")
    # ServersIP=("192.168.10.21" "192.168.10.22" "192.168.10.23"  "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32")
    # Servers=("node11" "node12" "node13" "node14" "node15" "node17" "node18" "node20" "node21" "node22")
    # ServersIP=("192.168.10.21" "192.168.10.22" "192.168.10.23" "192.168.10.24" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.30" "192.168.10.31" "192.168.10.32")
    # Servers=("node11" "node12" "node13" "node15" "node17" "node18" "node20" "node21" "node22" "node39")
    # ServersIP=("192.168.10.21" "192.168.10.22" "192.168.10.23" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.49")
    # Servers=("node12" "node13" "node15" "node17" "node18" "node19" "node20" "node21" "node22" "node39")
    # ServersIP=("192.168.10.22" "192.168.10.23" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.49")
    # Servers=("node12" "node13" "node14" "node15" "node17" "node18" "node19" "node20" "node21" "node22")
    # ServersIP=("192.168.10.22" "192.168.10.23" "192.168.10.24" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32")
    # Servers=("node13" "node15" "node17" "node18" "node19" "node20" "node21" "node22" "node37" "node39")
    # ServersIP=("192.168.10.23" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.47" "192.168.10.49")
    Servers=("node13" "node15" "node17" "node19" "node20" "node21" "node22" "node37" "node39" "node40")
    ServersIP=("192.168.10.23" "192.168.10.25" "192.168.10.27" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.47" "192.168.10.49" "192.168.10.50")
    Clients=("proj18" "proj19")
    ClientsIP=("192.168.50.18" "192.168.50.19")
    # Clients=("proj18")
    # ClientsIP=("192.168.50.18")
    Seeds=("node13" "node21" "node22")
    SeedsIP=("192.168.10.23" "192.168.10.31" "192.168.10.32")
    # Seeds=("node11" "node12" "node13" "node14" "node15" "node16" "node17" "node18" "node19" "node20")
    # SeedsIP=("192.168.10.21" "192.168.10.22" "192.168.10.23" "192.168.10.24" "192.168.10.25" "192.168.10.26" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30")
    NodeIP="192.168.10.31" # Only used for start-client.sh
    UserName="ymren"
    SudoPassword="ymren"
    HOME_PATH="/mnt/ssd"
elif [[ "$CLUSTER_NAME" == "2x" ]]; then
    # Servers=("node13" "node15" "node17" "node18" "node19" "node20" "node21" "node22" "node37" "node39" "node40" "node41" "node42" "node43" "node45")
    # ServersIP=("192.168.10.23" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.47" "192.168.10.49" "192.168.10.50" "192.168.10.51" "192.168.10.52" "192.168.10.53" "192.168.10.55")
    Servers=("node12" "node13" "node15" "node17" "node18" "node19" "node20" "node21" "node22" "node39" "node37" "node40" "node45" "node52" "node53")
    ServersIP=("192.168.10.22" "192.168.10.23" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.49" "192.168.10.47" "192.168.10.50" "192.168.10.55" "192.168.10.62" "192.168.10.63")
    # Clients=("proj18" "proj19")
    # ClientsIP=("192.168.50.18" "192.168.50.19")
    Clients=("proj18")
    ClientsIP=("192.168.50.18")
    Seeds=("node13" "node21" "node22")
    SeedsIP=("192.168.10.23" "192.168.10.31" "192.168.10.32")
    NodeIP="192.168.10.31" # Only used for start-client.sh
    UserName="ymren"
    SudoPassword="ymren"
    HOME_PATH="/mnt/ssd"
elif [[ "$CLUSTER_NAME" == "3x" ]]; then
    # Servers=("node13" "node15" "node17" "node18" "node19" "node20" "node21" "node22" "node37" "node39" "node40" "node41" "node42" "node43" "node45" "node46" "node47" "node48" "node52" "node53")
    # ServersIP=("192.168.10.23" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.47" "192.168.10.49" "192.168.10.50" "192.168.10.51" "192.168.10.52" "192.168.10.53" "192.168.10.55" "192.168.10.56" "192.168.10.57" "192.168.10.58" "192.168.10.62" "192.168.10.63")
    Servers=("node12" "node13" "node14" "node15" "node17" "node18" "node19" "node20" "node21" "node22" "node37" "node39" "node40" "node41" "node42" "node43" "node45" "node48" "node52" "node53")
    ServersIP=("192.168.10.22" "192.168.10.23" "192.168.10.24" "192.168.10.25" "192.168.10.27" "192.168.10.28" "192.168.10.29" "192.168.10.30" "192.168.10.31" "192.168.10.32" "192.168.10.47" "192.168.10.49" "192.168.10.50" "192.168.10.51" "192.168.10.52" "192.168.10.53" "192.168.10.55" "192.168.10.58" "192.168.10.62" "192.168.10.63")
    # Clients=("proj18" "proj19")
    # ClientsIP=("192.168.10.118" "192.168.10.119")
    Clients=("proj18")
    ClientsIP=("192.168.10.118")
    Seeds=("node13" "node21" "node22")
    SeedsIP=("192.168.10.23" "192.168.10.31" "192.168.10.32")
    NodeIP="192.168.10.31" # Only used for start-client.sh
    UserName="ymren"
    SudoPassword="ymren"
    HOME_PATH="/mnt/ssd"
elif [[ "$CLUSTER_NAME" == "4x" ]]; then
    Servers=("node41" "node42" "node43" "node45")
    ServersIP=("192.168.10.51" "192.168.10.52" "192.168.10.53" "192.168.10.55")
    Clients=("node49")
    ClientsIP=("192.168.10.59")
    # Clients=("proj18")
    # ClientsIP=("192.168.10.118")
    Seeds=("node41" "node42")
    SeedsIP=("192.168.10.51" "192.168.10.52")
    NodeIP="192.168.10.51" # Only used for start-client.sh
    UserName="ymren"
    SudoPassword="ymren"
    HOME_PATH="/home/ymren"
else
    echo "Invalid cluster name $CLUSTER_NAME"
    exit 1
fi




ServerNumber=${#Servers[@]}
Coordinators=""
for i in "${!ServersIP[@]}"; do
    Coordinators+="${ServersIP[i]}"
    if [ $i -ne $((${#ServersIP[@]} - 1)) ]; then
        Coordinators+=","
    fi
done

SEEDS=""
for i in "${!SeedsIP[@]}"; do
    SEEDS+="${SeedsIP[i]}"
    if [ $i -ne $((${#SeedsIP[@]} - 1)) ]; then
        SEEDS+=","
    fi
done

ALL_SERVERS=""
for i in "${!ServersIP[@]}"; do
    ALL_SERVERS+="${ServersIP[i]}"
    if [ $i -ne $((${#ServersIP[@]} - 1)) ]; then
        ALL_SERVERS+=","
    fi
done

AllNodes=("${Servers[@]}")
AllNodes+=("${Clients[@]}")
# echo "All nodes list is ${AllNodes}"

NumTokens=1
PathToServer="${HOME_PATH}/${PROJECT_NAME}/servers/$SCHEME"
PathToScripts="${HOME_PATH}/${PROJECT_NAME}/scripts"
PathToClient="${HOME_PATH}/${PROJECT_NAME}/client"
PathToBackup="${HOME_PATH}/backups"
ClientLogDir="${PathToClient}/logs/"
NetworkInterface="enp1s0f0"
DiskDevice="ssd"
PathToResultDir="$PathToServer/metrics"
PathToLogDir="$PathToServer/logs"
ALL_RESULTS="/home/ymren/all_results.txt"

if [[ "$SCHEME" == "" || "$BACKUP_MODE" == "" ]]; then
    echo "Please specify the SCHEME and BACKUP_MODE"
elif [ "$BACKUP_MODE" == "local" ]; then
    PathToBackup="/home/ymren/backups"
elif [ "$BACKUP_MODE" == "remote" ]; then
    echo "Do nothing"
else
    echo "Invalid BACKUP_MODE $BACKUP_MODE"
fi
