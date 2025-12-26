#!/bin/bash


# The reuslt file for plot
OVERALL_THPT_RES="throughput.txt"
OVERALL_LATENCY_RES="latency.txt"
OVERALL_RESOURCE_RES="resource.txt"

THPT_TITLE_LINE="Scheme        Workload      Thpt       SD"
LATENCY_TITLE_LINE="Scheme    Workload    Percentile      Latency       SD"
RESOURCE_TITLE_LINE="Scheme    Workload    Resource      Mean        SD"

# TITLE_LINE="Type        CL      Mean        SD"
CONSISTENCY_THPT_TITLE_LINE="Type    Consistency    Thpt    SD"
CONSISTENCY_LATENCY_TITLE_LINE="Type    Consistency    Latency    SD"
DISTRIBUTION_THPT_TITLE_LINE="Type      Distribution    Thpt        SD"
DISTRIBUTION_LATENCY_TITLE_LINE="Type   Distribution    Latency     SD"
RF_THPT_TITLE_LINE="Type      RF    Thpt        SD"
RF_LATENCY_TITLE_LINE="Type   RF    Thpt        SD"
VALUE_THPT_TITLE_LINE="Type      ValueSize    Thpt        SD"
VALUE_LATENCY_TITLE_LINE="Type   ValueSize    Thpt        SD"
CLIENT_THPT_TITLE_LINE="Type      Client    Thpt        SD"
CLIENT_LATENCY_TITLE_LINE="Type   Client    Thpt        SD"




function extract_value() {
    if [[ $1 == *"count"* ]]; then
        awk -v pattern="$1" '$0 ~ pattern {print $NF}' "$2"
    else
        awk -v pattern="$1" '$0 ~ pattern {printf "%.2f\n", $NF}' "$2"
    fi
    # awk -v pattern="$1" '$0 ~ pattern {print $NF}' "$2"
    # awk -v pattern="$1" '$0 ~ pattern {printf "%.2f\n", $NF}' "$2"
}



function initResultFiles() {
    run_dir=$1
    exp_num=$2

    OVERALL_THPT_RES="${run_dir}/${OVERALL_THPT_RES}"
    OVERALL_LATENCY_RES="${run_dir}/${OVERALL_LATENCY_RES}"
    OVERALL_RESOURCE_RES="${run_dir}/${OVERALL_RESOURCE_RES}"

    echo "the run_dir: ${run_dir}, exp_num is ${exp_num}"
    if [ "${exp_num}" == "ycsb" ]; then
        > "$OVERALL_THPT_RES" && echo "$THPT_TITLE_LINE" > "$OVERALL_THPT_RES"
        > "$OVERALL_LATENCY_RES" && echo "$LATENCY_TITLE_LINE" > "$OVERALL_LATENCY_RES"
        > "$OVERALL_RESOURCE_RES" && echo "$RESOURCE_TITLE_LINE" > "$OVERALL_RESOURCE_RES"
    elif [ "${exp_num}" == "consistency" ]; then
        > "$OVERALL_THPT_RES" && echo "$CONSISTENCY_THPT_TITLE_LINE" > "$OVERALL_THPT_RES"
        > "$OVERALL_LATENCY_RES" && echo "$CONSISTENCY_LATENCY_TITLE_LINE" > "$OVERALL_LATENCY_RES"
    elif [ "${exp_num}" == "distribution" ]; then
        > "$OVERALL_THPT_RES" && echo "$DISTRIBUTION_THPT_TITLE_LINE" > "$OVERALL_THPT_RES"
        > "$OVERALL_LATENCY_RES" && echo "$DISTRIBUTION_LATENCY_TITLE_LINE" > "$OVERALL_LATENCY_RES"
    elif [ "${exp_num}" == "rf" ]; then
        > "$OVERALL_THPT_RES" && echo "$RF_THPT_TITLE_LINE" > "$OVERALL_THPT_RES"
        > "$OVERALL_LATENCY_RES" && echo "$RF_LATENCY_TITLE_LINE" > "$OVERALL_LATENCY_RES"
    elif [ "${exp_num}" == "value" ]; then
        > "$OVERALL_THPT_RES" && echo "$VALUE_THPT_TITLE_LINE" > "$OVERALL_THPT_RES"
        > "$OVERALL_LATENCY_RES" && echo "$VALUE_LATENCY_TITLE_LINE" > "$OVERALL_LATENCY_RES"
    elif [ "${exp_num}" == "client" ]; then
        > "$OVERALL_THPT_RES" && echo "$CLIENT_THPT_TITLE_LINE" > "$OVERALL_THPT_RES"
        > "$OVERALL_LATENCY_RES" && echo "$CLIENT_LATENCY_TITLE_LINE" > "$OVERALL_LATENCY_RES"
    fi
}

function process_directory() {
    local run_dir=$1
    local exp_num=$2

    scheme_name=$(basename "$(pwd)")
    # Initialize the output files
    initResultFiles $run_dir $exp_num

    for exp_dir in "$run_dir"/*/; do
        echo "Processing directory: $exp_dir"
        local exp_name=$(basename "$exp_dir")
        process_sub_directory "$exp_dir" "$exp_name" "$scheme_name" "$exp_num"
        
    done

}

function process_sub_directory {


    local exp_dir=$1
    local exp_name=$2
    local scheme_name=$3
    local exp_num=$4
    declare -A overall_data

    for round_dir in "$exp_dir"/*/; do
        round=$(basename "$round_dir")
        declare -A round_data


        disk_read_io_of_all_nodes=()
        disk_write_io_of_all_nodes=()
        user_time_of_all_nodes=()
        sys_time_of_all_nodes=()
        local_read_count_of_all_nodes=()
        local_read_latency_of_all_nodes=()
        coordinator_read_count_of_all_nodes=()
        coordinator_read_latency_of_all_nodes=()
        local_write_count_of_all_nodes=()
        local_write_latency_of_all_nodes=()
        coordinator_write_count_of_all_nodes=()
        coordinator_write_latency_of_all_nodes=()
        local_scan_count_of_all_nodes=()
        local_scan_latency_of_all_nodes=()
        coordinator_scan_count_of_all_nodes=()
        coordinator_scan_latency_of_all_nodes=()
        coordinator_read_time_of_all_nodes=()
        selection_time_of_all_nodes=()
        local_read_time_of_all_nodes=()
        write_memtable_time_of_all_nodes=()
        write_wal_time_of_all_nodes=()
        flush_time_of_all_nodes=()
        compaction_time_of_all_nodes=()
        read_cache_time_of_all_nodes=()
        read_memtable_time_of_all_nodes=()
        read_sstable_time_of_all_nodes=()
        read_wait_time_of_all_nodes=()
        read_two_layer_log_time_of_all_nodes=()
        merge_sort_time_of_all_nodes=()
        overall_disk_io_of_all_nodes=()
        overall_network_io_of_all_nodes=()
        overall_cpu_time_of_all_nodes=()
        mem_size_of_all_nodes=()
        read_network_io_of_all_nodes=()
        write_network_io_of_all_nodes=()
        forward_requests_of_all_nodes=0

        for node_dir in "$round_dir"node*; do
            node_name=$(basename "$node_dir")
            # echo "Processing $node_dir"

            # Get the Memory
            mem_file="$node_dir/metrics/SampleExpName_Running_memory_usage.txt"
            mem_size=$(calculate_average_memory_usage "$mem_file")
            
            # Get the CPU 
            cpu_file="$node_dir/metrics/After-normal-run_cpu_summary.txt"
            uptime=$(printf "%.0f" $(extract_value "Process uptime" "$cpu_file"))
            user_time=$(printf "%.0f" $(extract_value "User time" "$cpu_file"))
            sys_time=$(printf "%.0f" $(extract_value "System time" "$cpu_file"))

            # Get the disk I/O
            disk_io_file_after="$node_dir/metrics/After-normal-run_disk_io_total.txt"
            disk_io_file_before="$node_dir/metrics/Before-run_disk_io_total.txt"

            after_read=$(extract_value "Disk KiB read" "$disk_io_file_after")
            before_read=$(extract_value "Disk KiB read" "$disk_io_file_before")

            after_read=$(printf "%f" $after_read)
            before_read=$(printf "%f" $before_read)
            
            disk_read_io=$(echo "scale=0; (${after_read:-0} - ${before_read:-0}) / 1024" | bc)

            after_written=$(extract_value "Disk KiB written" "$disk_io_file_after")
            before_written=$(extract_value "Disk KiB written" "$disk_io_file_before")
            disk_write_io=$(echo "scale=0; (${after_written:-0} - ${before_written:-0}) / 1024" | bc)

            # echo "=======================Disk I/O diff=================================="
            # echo "Disk I/O Difference for $node_name:"
            # echo "Read Difference (MiB): $disk_read_io"
            # echo "Write Difference (MiB): $disk_write_io"
            # echo "======================================================================"


            # Get the network I/O
            network_file_after="$node_dir/metrics/After-normal-run_network_summary.txt"
            network_file_before="$node_dir/metrics/Before-run_network_summary.txt"

            after_received=$(extract_value "Bytes received" "$network_file_after")
            before_received=$(extract_value "Bytes received" "$network_file_before")
            network_recv_io=$(echo "scale=0; (${after_received:-0} - ${before_received:-0}) / 1048576" | bc) # MiB

            after_sent=$(extract_value "Bytes sent" "$network_file_after")
            before_sent=$(extract_value "Bytes sent" "$network_file_before")
            network_send_io=$(echo "scale=0; (${after_sent:-0} - ${before_sent:-0}) / 1048576" | bc)


            overall_disk_io=$(echo "scale=0; $disk_read_io + $disk_write_io" | bc)
            overall_network_io=$(echo "scale=0; $network_recv_io + $network_send_io" | bc)
            overall_cpu_time=$(echo "scale=0; $user_time + $sys_time" | bc)
            # Get the read and write counts
            # db_stats_file_after="$node_dir/metrics/After-normal-run_db_stats.txt"
            # db_stats_file_before="$node_dir/metrics/Before-run_db_stats.txt"

            # after_reads=$(extract_value "Local read count" "$db_stats_file_after")
            # before_reads=$(extract_value "Local read count" "$db_stats_file_before")
            # read_count=$(echo "scale=0; (${after_reads:-0} - ${before_reads:-0})" | bc)

            # after_writes=$(extract_value "Local write count" "$db_stats_file_after")
            # before_writes=$(extract_value "Local write count" "$db_stats_file_before")
            # write_count=$(echo "scale=0; (${after_writes:-0} - ${before_writes:-0})" | bc)

            break_down_file="$node_dir/metrics/breakdown.txt"
            local_read_count=$(extract_value "Local read count" "$break_down_file")
            local_read_latency=$(extract_value "Local read latency" "$break_down_file")
            coordinator_read_count=$(extract_value "Coordinator read count" "$break_down_file")
            coordinator_read_latency=$(extract_value "Coordinator read latency" "$break_down_file")
            local_write_count=$(extract_value "Local write count" "$break_down_file")
            local_write_latency=$(extract_value "Local write latency" "$break_down_file")
            coordinator_write_count=$(extract_value "Coordinator write count" "$break_down_file")
            coordiantor_write_latency=$(extract_value "Coordinator write latency" "$break_down_file")
            local_scan_count=$(extract_value "Local range count" "$break_down_file")
            local_scan_latency=$(extract_value "Local range latency" "$break_down_file")
            coordinator_scan_count=$(extract_value "Coordinator scan count" "$break_down_file")
            coordinator_scan_latency=$(extract_value "Coordinator scan latency" "$break_down_file")


            ############## calculate the read and write net io
            write_net_io=$(echo "scale=2; ($local_write_count) / 1024 / 1024" | bc)
            read_net_io=$(echo "scale=2; ($local_read_count) / 1024 / 1024" | bc)
            # read_net_io=$(echo "scale=0; ($overall_network_io - write_net_io)" | bc)

            # For the operation breakdown time, we use the mircro seconds, as each KV pair is 1 KB, so it is the 1KiB operation breakdown time.
            # We can also regard this result as 1 MiB operation breakdown time, and the unit is milliseconds.
            coordinator_read_time=$(extract_value "CoordinatorReadTime" "$break_down_file")
            coordinator_read_time=$(echo "$coordinator_read_time * 1000 / $coordinator_read_count" | bc)
            local_read_time=$(extract_value "LocalReadTime" "$break_down_file")
            local_read_time=$(echo "$local_read_time * 1000 / $local_read_count" | bc)
            selection_time=$(echo "scale=0; $coordinator_read_time - $local_read_time" | bc)
            write_memtable_time=$(extract_value "WriteMemTable" "$break_down_file")
            write_memtable_time=$(echo "$write_memtable_time * 1000 / $local_write_count" | bc)
            write_wal_time=$(extract_value "CommitLog" "$break_down_file")
            write_wal_time=$(echo "$write_wal_time * 1000 / $local_write_count" | bc)
            flush_time=$(extract_value "Flush" "$break_down_file")
            flush_time=$(echo "$flush_time * 1000 / $local_write_count" | bc)
            compaction_time=$(extract_value "Compaction" "$break_down_file")
            compaction_time=$(echo "$compaction_time * 1000 / $local_write_count" | bc)
            read_cache_time=$(extract_value "ReadCache" "$break_down_file")
            read_cache_time=$(echo "$read_cache_time * 1000 / $local_read_count" | bc)
            read_memtable_time=$(extract_value "ReadMemTable" "$break_down_file")
            read_memtable_time=$(echo "$read_memtable_time * 1000 / $local_read_count" | bc)
            read_sstable_time=$(extract_value "ReadSSTable" "$break_down_file")
            read_sstable_time=$(echo "$read_sstable_time * 1000 / $local_read_count" | bc)
            read_wait_time=$(extract_value "ReadWaitTime" "$break_down_file")
            read_wait_time=$(echo "$read_wait_time * 1000 / $local_read_count" | bc)
            read_two_layer_log_time=$(extract_value "ReadTwoLayerLog" "$break_down_file")
            read_two_layer_log_time=$(echo "$read_two_layer_log_time * 1000 / $local_read_count" | bc)
            merge_sort_time=$(extract_value "MergeSort" "$break_down_file")
            merge_sort_time=$(echo "$merge_sort_time * 1000 / $local_write_count" | bc)

            forwarded_requests=$(extract_value "ForwardedReadRequest" "$break_down_file")



            eval "round_data[$node_name,node_name]=\"$node_name\""
            eval "round_data[$node_name,uptime]+=\"$uptime \""
            eval "round_data[$node_name,user_time]+=\"$user_time \""
            eval "round_data[$node_name,sys_time]+=\"$sys_time \""
            eval "round_data[$node_name,disk_read_io]+=\"$disk_read_io \""
            eval "round_data[$node_name,disk_write_io]+=\"$disk_write_io \""
            eval "round_data[$node_name,network_recv_io]+=\"$network_recv_io \""
            eval "round_data[$node_name,network_send_io]+=\"$network_send_io \""
            eval "round_data[$node_name,overall_disk_io]+=\"$overall_disk_io \""
            eval "round_data[$node_name,overall_network_io]+=\"$overall_network_io \""
            eval "round_data[$node_name,overall_cpu_time]+=\"$overall_cpu_time \""
            eval "round_data[$node_name,read_net_io]+=\"$read_net_io \""
            eval "round_data[$node_name,write_net_io]+=\"$write_net_io \""
            eval "round_data[$node_name,mem_size]+=\"$mem_size \""
            # eval "round_data[$node_name,read_count]+=\"s"$write_count \""
            eval "round_data[$node_name,local_read_count]+=\"$local_read_count \""
            eval "round_data[$node_name,local_read_latency]+=\"$local_read_latency \""
            eval "round_data[$node_name,coordinator_read_count]+=\"$coordinator_read_count \""
            eval "round_data[$node_name,coordinator_read_latency]+=\"$coordinator_read_latency \""
            eval "round_data[$node_name,local_write_count]+=\"$local_write_count \""
            eval "round_data[$node_name,local_write_latency]+=\"$local_write_latency \""
            eval "round_data[$node_name,coordinator_write_count]+=\"$coordinator_write_count \""
            eval "round_data[$node_name,coordinator_write_latency]+=\"$coordiantor_write_latency \""
            eval "round_data[$node_name,local_scan_count]+=\"$local_scan_count \""
            eval "round_data[$node_name,local_scan_latency]+=\"$local_scan_latency \""
            eval "round_data[$node_name,coordinator_scan_count]+=\"$coordinator_scan_count \""
            eval "round_data[$node_name,coordinator_scan_latency]+=\"$coordinator_scan_latency \""
            eval "round_data[$node_name,coordinator_read_time]+=\"$coordinator_read_time \""
            eval "round_data[$node_name,local_read_time]+=\"$local_read_time \""
            eval "round_data[$node_name,selection_time]+=\"$selection_time \""
            eval "round_data[$node_name,write_memtable_time]+=\"$write_memtable_time \""
            eval "round_data[$node_name,write_wal_time]+=\"$write_wal_time \""
            eval "round_data[$node_name,flush_time]+=\"$flush_time \""
            eval "round_data[$node_name,compaction_time]+=\"$compaction_time \""
            eval "round_data[$node_name,read_cache_time]+=\"$read_cache_time \""
            eval "round_data[$node_name,read_memtable_time]+=\"$read_memtable_time \""
            eval "round_data[$node_name,read_sstable_time]+=\"$read_sstable_time \""
            eval "round_data[$node_name,read_wait_time]+=\"$read_wait_time \""
            eval "round_data[$node_name,read_two_layer_log_time]+=\"$read_two_layer_log_time \""
            eval "round_data[$node_name,merge_sort_time]+=\"$merge_sort_time \""
            eval "round_data[$node_name,forwarded_requests]+=\"$forwarded_requests \""

            user_time_of_all_nodes+=("$user_time")
            sys_time_of_all_nodes+=("$sys_time")
            disk_read_io_of_all_nodes+=("$disk_read_io")
            disk_write_io_of_all_nodes+=("$disk_write_io")
            local_read_count_of_all_nodes+=("$local_read_count")
            local_read_latency_of_all_nodes+=("$local_read_latency")
            coordinator_read_count_of_all_nodes+=("$coordinator_read_count")
            coordinator_read_latency_of_all_nodes+=("$coordinator_read_latency")
            local_write_count_of_all_nodes+=("$local_write_count")
            local_write_latency_of_all_nodes+=("$local_write_latency")
            coordinator_write_count_of_all_nodes+=("$coordinator_write_count")
            coordinator_write_latency_of_all_nodes+=("$coordiantor_write_latency")
            local_scan_count_of_all_nodes+=("$local_scan_count")
            local_scan_latency_of_all_nodes+=("$local_scan_latency")
            coordinator_scan_count_of_all_nodes+=("$coordinator_scan_count")
            coordinator_scan_latency_of_all_nodes+=("$coordinator_scan_latency")
            coordinator_read_time_of_all_nodes+=("$coordinator_read_time")
            local_read_time_of_all_nodes+=("$local_read_time")
            selection_time_of_all_nodes+=("$selection_time")
            write_memtable_time_of_all_nodes+=("$write_memtable_time")
            write_wal_time_of_all_nodes+=("$write_wal_time")
            flush_time_of_all_nodes+=("$flush_time")
            compaction_time_of_all_nodes+=("$compaction_time")
            read_cache_time_of_all_nodes+=("$read_cache_time")
            read_memtable_time_of_all_nodes+=("$read_memtable_time")
            read_sstable_time_of_all_nodes+=("$read_sstable_time")
            read_wait_time_of_all_nodes+=("$read_wait_time")
            read_two_layer_log_time_of_all_nodes+=("$read_two_layer_log_time")
            merge_sort_time_of_all_nodes+=("$merge_sort_time")
            forward_requests_of_all_nodes=$(echo "$forward_requests_of_all_nodes + $forwarded_requests" | bc)
            overall_disk_io_of_all_nodes+=("$overall_disk_io")
            overall_network_io_of_all_nodes+=("$overall_network_io")
            overall_cpu_time_of_all_nodes+=("$overall_cpu_time")
            mem_size_of_all_nodes+=("$mem_size")
            read_network_io_of_all_nodes+=("$read_net_io")
            write_network_io_of_all_nodes+=("$write_net_io")
        done

        # Get the average read latency
        # average_read_latency=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[READ\], AverageLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        average_read_latency=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[READ\], AverageLatency(us), " "{}" | awk -F ", " "{printf \"%.0f\", \$3}"' \;)
        echo "Average Read Latency: $average_read_latency"
        meidan_read_latency=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[READ\], MedianLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        tail_read_latency_75th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[READ\], 75thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        tail_read_latency_95th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[READ\], 95thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        tail_read_latency_99th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[READ\], 99thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        tail_read_latency_999th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[READ\], 999thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        average_update_latency=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[UPDATE\], AverageLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        tail_update_latency_99th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[UPDATE\], 99thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        average_scan_latency=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[SCAN\], AverageLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        tail_scan_latency_99th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[SCAN\], 99thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)

        overall_latency_average=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], AverageLatency(us), " "{}" | awk -F ", " "{printf \"%.0f\", \$3}"' \;)
        overall_latency_50th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], MedianLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        overall_latency_75th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], 75thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        overall_latency_95th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], 95thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        overall_latency_99th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], 99thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        overall_latency_999th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], 999thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)


        # average_scan_latency=$(echo "scale=0; $average_scan_latency" | bc)
        # tail_scan_latency_99th=$(echo "scale=0; $tail_scan_latency_99th" | bc)
        average_insert_latency=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[INSERT\], AverageLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        tail_insert_latency_99th=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[INSERT\], 99thPercentileLatency(us), " "{}" | awk -F ", " "{print \$3}"' \;)
        overall_runtime=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], RunTime(ms), " "{}" | awk -F ", " "{print \$3}"' \;)
        overall_throughput=$(find $round_dir -name "*.log" -exec sh -c 'grep "\[OVERALL\], Throughput(ops/sec), " "{}" | awk -F ", " "{print \$3}"' \;)
        overall_throughput=$(echo "scale=2; $overall_throughput / 1000" | bc) # KOPS to MOPS
        avg_user_time=$(echo "scale=0; ($(IFS=+; echo "(${user_time_of_all_nodes[*]})") / ${#user_time_of_all_nodes[@]})" | bc)
        avg_sys_time=$(echo "scale=0; ($(IFS=+; echo "(${sys_time_of_all_nodes[*]})") / ${#sys_time_of_all_nodes[@]})" | bc)
        avg_disk_read_io=$(echo "scale=0; ($(IFS=+; echo "(${disk_read_io_of_all_nodes[*]})") / ${#disk_read_io_of_all_nodes[@]})" | bc)
        avg_disk_write_io=$(echo "scale=0; ($(IFS=+; echo "(${disk_write_io_of_all_nodes[*]})") / ${#disk_write_io_of_all_nodes[@]})" | bc)
        avg_overall_disk_io=$(echo "scale=0; ($(IFS=+; echo "(${overall_disk_io_of_all_nodes[*]})") / ${#overall_disk_io_of_all_nodes[@]})" | bc)
        avg_overall_network_io=$(echo "scale=0; ($(IFS=+; echo "(${overall_network_io_of_all_nodes[*]})") / ${#overall_network_io_of_all_nodes[@]})" | bc)
        avg_overall_cpu_time=$(echo "scale=0; ($(IFS=+; echo "(${overall_cpu_time_of_all_nodes[*]})") / ${#overall_cpu_time_of_all_nodes[@]})" | bc)
        avg_mem_size=$(echo "scale=2; ($(IFS=+; echo "(${mem_size_of_all_nodes[*]})") / ${#mem_size_of_all_nodes[@]})" | bc)
        echo "###########################################################################################Average mem size: $avg_mem_size"
        average_local_read_latency=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] local_read_latency_of_all_nodes[@])
        echo "Average Local Read Latency: $average_local_read_latency"
        average_coordinator_read_latency=$(calculate_arithmetic_mean coordinator_read_count_of_all_nodes[@] coordinator_read_latency_of_all_nodes[@])

        average_local_write_latency=$(calculate_arithmetic_mean local_write_count_of_all_nodes[@] local_write_latency_of_all_nodes[@])
        average_coordinator_write_latency=$(calculate_arithmetic_mean coordinator_write_count_of_all_nodes[@] coordinator_write_latency_of_all_nodes[@])

        average_local_scan_latency=$(calculate_arithmetic_mean local_scan_count_of_all_nodes[@] local_scan_latency_of_all_nodes[@])
        average_coordinator_scan_latency=$(calculate_arithmetic_mean coordinator_scan_count_of_all_nodes[@] coordinator_scan_latency_of_all_nodes[@])

        average_coordinator_read_time=$(calculate_arithmetic_mean coordinator_read_count_of_all_nodes[@] coordinator_read_time_of_all_nodes[@])
        cov_coordinator_read_time=$(calculate_cov coordinator_read_time_of_all_nodes[@])
        std_local_read_time=$(calculate_std local_read_time_of_all_nodes[@])
        average_local_read_time=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] local_read_time_of_all_nodes[@])
        average_selection_time=$(calculate_arithmetic_mean coordinator_read_count_of_all_nodes[@] selection_time_of_all_nodes[@])
        average_write_memtable_time=$(calculate_arithmetic_mean local_write_count_of_all_nodes[@] write_memtable_time_of_all_nodes[@])
        average_write_wal_time=$(calculate_arithmetic_mean local_write_count_of_all_nodes[@] write_wal_time_of_all_nodes[@])
        average_flush_time=$(calculate_arithmetic_mean local_write_count_of_all_nodes[@] flush_time_of_all_nodes[@])
        average_compaction_time=$(calculate_arithmetic_mean local_write_count_of_all_nodes[@] compaction_time_of_all_nodes[@])
        average_read_cache_time=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] read_cache_time_of_all_nodes[@])
        average_read_memtable_time=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] read_memtable_time_of_all_nodes[@])
        average_read_sstable_time=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] read_sstable_time_of_all_nodes[@])
        average_read_wait_time=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] read_wait_time_of_all_nodes[@])
        average_read_two_layer_log_time=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] read_two_layer_log_time_of_all_nodes[@])
        average_merge_sort_time=$(calculate_arithmetic_mean local_read_count_of_all_nodes[@] merge_sort_time_of_all_nodes[@])


        # replica_selection_cost=$(bc <<< "scale=0; $average_coordinator_read_latency - $average_local_read_latency")
        replica_selection_cost=$(echo "$average_coordinator_read_latency - $average_local_read_latency" | bc)
        echo "Replica Selection Cost: $replica_selection_cost"
        # read_network_cost=$(bc <<< "$average_read_latency - $average_local_read_latency")
        echo "Average Read Latency: $average_read_latency, Average Local Read Latency: $average_local_read_latency"
        read_network_cost=$(echo "${average_read_latency} - ${average_coordinator_read_latency}" | bc)
        echo "Read Network Cost: $read_network_cost"

        eval "round_data[average_read_latency]=\"$average_read_latency \""
        eval "rount_data[median_read_latency]=\"$meidan_read_latency \""
        eval "round_data[tail_read_latency_75th]=\"$tail_read_latency_75th \""
        eval "round_data[tail_read_latency_95th]=\"$tail_read_latency_95th \""
        eval "round_data[tail_read_latency_99th]=\"$tail_read_latency_99th \""
        eval "round_data[tail_read_latency_999th]=\"$tail_read_latency_999th \""
        eval "round_data[average_update_latency]=\"$average_update_latency \""
        eval "round_data[tail_update_latency_99th]=\"$tail_update_latency_99th \""
        eval "round_data[average_scan_latency]=\"$average_scan_latency \""
        eval "round_data[tail_scan_latency_99th]=\"$tail_scan_latency_99th \""
        eval "round_data[average_insert_latency]=\"$average_insert_latency \""
        eval "round_data[tail_insert_latency_99th]=\"$tail_insert_latency_99th \""
        eval "round_data[overall_latency_average]=\"$overall_latency_average \""
        eval "round_data[overall_latency_50th]=\"$overall_latency_50th \""
        eval "round_data[overall_latency_75th]=\"$overall_latency_75th \""
        eval "round_data[overall_latency_95th]=\"$overall_latency_95th \""
        eval "round_data[overall_latency_99th]=\"$overall_latency_99th \""
        eval "round_data[overall_latency_999th]=\"$overall_latency_999th \""
        eval "round_data[overall_runtime]=\"$overall_runtime \""
        eval "round_data[overall_throughput]=\"$overall_throughput \""
        eval "round_data[average_user_time]=\"$avg_user_time\""
        eval "round_data[average_sys_time]=\"$avg_sys_time\""
        eval "round_data[average_disk_read_io]=\"$avg_disk_read_io\""
        eval "round_data[average_disk_write_io]=\"$avg_disk_write_io\""
        eval "round_data[average_overall_disk_io]=\"$avg_overall_disk_io\""
        eval "round_data[average_overall_network_io]=\"$avg_overall_network_io\""
        eval "round_data[average_overall_cpu_time]=\"$avg_overall_cpu_time\""
        eval "round_data[avg_mem_size]=\"$avg_mem_size\""
        eval "round_data[average_local_read_latency]=\"$average_local_read_latency\""
        eval "round_data[average_coordinator_read_latency]=\"$average_coordinator_read_latency\""
        eval "round_data[average_local_write_latency]=\"$average_local_write_latency\""
        eval "round_data[average_coordinator_write_latency]=\"$average_coordinator_write_latency\""
        eval "round_data[average_local_scan_latency]=\"$average_local_scan_latency\""
        eval "round_data[average_coordinator_scan_latency]=\"$average_coordinator_scan_latency\""
        eval "round_data[read_network_cost]=\"$read_network_cost\""
        eval "round_data[replica_selection_cost]=\"$replica_selection_cost\""
        eval "round_data[average_coordinator_read_time]=\"$average_coordinator_read_time\""
        eval "round_data[cov_coordinator_read_time]=\"$cov_coordinator_read_time\""
        eval "round_data[std_local_read_time]=\"$std_local_read_time\""
        eval "round_data[average_local_read_time]=\"$average_local_read_time\""
        eval "round_data[average_selection_time]=\"$average_selection_time\""
        eval "round_data[average_write_memtable_time]=\"$average_write_memtable_time\""
        eval "round_data[average_write_wal_time]=\"$average_write_wal_time\""
        eval "round_data[average_flush_time]=\"$average_flush_time\""
        eval "round_data[average_compaction_time]=\"$average_compaction_time\""
        eval "round_data[average_read_cache_time]=\"$average_read_cache_time\""
        eval "round_data[average_read_memtable_time]=\"$average_read_memtable_time\""
        eval "round_data[average_read_sstable_time]=\"$average_read_sstable_time\""
        eval "round_data[average_read_wait_time]=\"$average_read_wait_time\""
        eval "round_data[average_read_two_layer_log_time]=\"$average_read_two_layer_log_time\""
        eval "round_data[average_merge_sort_time]=\"$average_merge_sort_time\""
        eval "round_data[forward_requests_of_all_nodes]=\"$forward_requests_of_all_nodes\""


        # echo "=======================Round Data=================================="
        eval "overall_data[$round,average_read_latency]=\"$average_read_latency \""
        eval "overall_data[$round,median_read_latency]=\"$meidan_read_latency \""
        eval "overall_data[$round,tail_read_latency_75th]=\"$tail_read_latency_75th \""
        eval "overall_data[$round,tail_read_latency_95th]=\"$tail_read_latency_95th \""
        eval "overall_data[$round,tail_read_latency_99th]=\"$tail_read_latency_99th \""
        eval "overall_data[$round,tail_read_latency_999th]=\"$tail_read_latency_999th \""
        eval "overall_data[$round,average_update_latency]=\"$average_update_latency \""
        eval "overall_data[$round,tail_update_latency_99th]=\"$tail_update_latency_99th \""
        eval "overall_data[$round,average_scan_latency]=\"$average_scan_latency \""
        eval "overall_data[$round,tail_scan_latency_99th]=\"$tail_scan_latency_99th \""
        eval "overall_data[$round,average_insert_latency]=\"$average_insert_latency \""
        eval "overall_data[$round,tail_insert_latency_99th]=\"$tail_insert_latency_99th \""
        eval "overall_data[$round,overall_latency_average]=\"$overall_latency_average \""
        eval "overall_data[$round,overall_latency_50th]=\"$overall_latency_50th \""
        eval "overall_data[$round,overall_latency_75th]=\"$overall_latency_75th \""
        eval "overall_data[$round,overall_latency_95th]=\"$overall_latency_95th \""
        eval "overall_data[$round,overall_latency_99th]=\"$overall_latency_99th \""
        eval "overall_data[$round,overall_latency_999th]=\"$overall_latency_999th \""
        eval "overall_data[$round,overall_runtime]=\"$overall_runtime \""
        eval "overall_data[$round,overall_throughput]=\"$overall_throughput \""
        eval "overall_data[$round,average_user_time]=\"$avg_user_time\""
        eval "overall_data[$round,average_sys_time]=\"$avg_sys_time\""
        eval "overall_data[$round,average_disk_read_io]=\"$avg_disk_read_io\""
        eval "overall_data[$round,average_disk_write_io]=\"$avg_disk_write_io\""
        eval "overall_data[$round,average_overall_disk_io]=\"$avg_overall_disk_io\""
        eval "overall_data[$round,average_overall_network_io]=\"$avg_overall_network_io\""
        eval "overall_data[$round,average_overall_cpu_time]=\"$avg_overall_cpu_time\""
        eval "overall_data[$round,avg_mem_size]=\"$avg_mem_size\""
        eval "overall_data[$round,average_local_read_latency]=\"$average_local_read_latency\""
        eval "overall_data[$round,average_coordinator_read_latency]=\"$average_coordinator_read_latency\""
        eval "overall_data[$round,average_local_write_latency]=\"$average_local_write_latency\""
        eval "overall_data[$round,average_coordinator_write_latency]=\"$average_coordinator_write_latency\""
        eval "overall_data[$round,average_local_scan_latency]=\"$average_local_scan_latency\""
        eval "overall_data[$round,average_coordinator_scan_latency]=\"$average_coordinator_scan_latency\""
        eval "overall_data[$round,replica_selection_cost]=\"$replica_selection_cost\""
        eval "overall_data[$round,read_network_cost]=\"$read_network_cost\""
        eval "overall_data[$round,average_coordinator_read_time]=\"$average_coordinator_read_time\""
        eval "overall_data[$round,cov_coordinator_read_time]=\"$cov_coordinator_read_time\""
        eval "overall_data[$round,std_local_read_time]=\"$std_local_read_time\""
        eval "overall_data[$round,average_local_read_time]=\"$average_local_read_time\""
        eval "overall_data[$round,average_selection_time]=\"$average_selection_time\""
        eval "overall_data[$round,average_write_memtable_time]=\"$average_write_memtable_time\""
        eval "overall_data[$round,average_write_wal_time]=\"$average_write_wal_time\""
        eval "overall_data[$round,average_flush_time]=\"$average_flush_time\""
        eval "overall_data[$round,average_compaction_time]=\"$average_compaction_time\""
        eval "overall_data[$round,average_read_cache_time]=\"$average_read_cache_time\""
        eval "overall_data[$round,average_read_memtable_time]=\"$average_read_memtable_time\""
        eval "overall_data[$round,average_read_sstable_time]=\"$average_read_sstable_time\""
        eval "overall_data[$round,average_read_wait_time]=\"$average_read_wait_time\""
        eval "overall_data[$round,average_read_two_layer_log_time]=\"$average_read_two_layer_log_time\""
        eval "overall_data[$round,average_merge_sort_time]=\"$average_merge_sort_time\""
        eval "overall_data[$round,forward_requests_of_all_nodes]=\"$forward_requests_of_all_nodes\""
        eval "overall_data[$round,round]=\"$round\""

        # Output the results for each round
        print_round_results round_data $round "$exp_dir"
        unset round_data

    done

    # Output the overall results
    print_overall_results overall_data $exp_name $scheme_name $exp_num

    

}

calculate_average_memory_usage() {
    local file="$1"
    local total_gib=0
    local count=0

    while read -r line; do
        memory_kib=$(echo "$line" | grep -oP 'using \K[0-9]+')

        if [ -n "$memory_kib" ]; then
            memory_gib=$(echo "scale=6; $memory_kib / (1024 * 1024)" | bc)

            total_gib=$(echo "$total_gib + $memory_gib" | bc)
            count=$((count + 1))
        fi
    done < "$file"

    if [ $count -gt 0 ]; then
        average_gib=$(echo "scale=6; $total_gib / $count" | bc)
        # echo "Average memory usage: $average_gib GiB"
        echo "$average_gib"
    fi
}


calculate_std() {
    local data=("${!1}")
    local sum=0
    local sum_of_squares=0
    local mean=0
    local std_dev=0

    # calculate the sum
    for value in "${data[@]}"; do
        sum=$(echo "$sum + $value" | bc)
    done

    # calculate the mean
    mean=$(echo "scale=6; $sum / ${#data[@]}" | bc)

    for value in "${data[@]}"; do
        diff=$(echo "$value - $mean" | bc)
        square=$(echo "$diff * $diff" | bc)
        sum_of_squares=$(echo "$sum_of_squares + $square" | bc)
    done

    # calculate standard deviation
    std_dev=$(echo "scale=6; sqrt($sum_of_squares / ${#data[@]})" | bc)

    echo "$std_dev"

}



calculate_cov() {
    local data=("${!1}")
    local sum=0
    local sum_of_squares=0
    local mean=0
    local std_dev=0
    local cov=0

    # calculate the sum
    for value in "${data[@]}"; do
        sum=$(echo "$sum + $value" | bc)
    done

    # calculate the mean
    mean=$(echo "scale=6; $sum / ${#data[@]}" | bc)

    for value in "${data[@]}"; do
        diff=$(echo "$value - $mean" | bc)
        square=$(echo "$diff * $diff" | bc)
        sum_of_squares=$(echo "$sum_of_squares + $square" | bc)
    done

    # calculate standard deviation
    std_dev=$(echo "scale=6; sqrt($sum_of_squares / ${#data[@]})" | bc)

    # calculate coefficient of variation
    cov=$(echo "scale=6; ($std_dev / $mean)" | bc)

    echo "$cov"
}



calculate_arithmetic_mean() {
    local count_array=("${!1}")  # Array containing counts
    local value_array=("${!2}")  # Array containing values
    # echo "Count Array: ${count_array[@]}"
    # echo "Value Array: ${value_array[@]}"

    local num_attributes="${#count_array[@]}"
    
    if [ "$num_attributes" -ne "${#value_array[@]}" ]; then
        echo "Error: Number of elements in the arrays do not match."
        # return 1
    fi

    local total_sum=0
    local total_count=0

    # Iterate through each attribute
    for ((i=0; i<num_attributes; i++)); do
        local count="${count_array[$i]}"
        local value="${value_array[$i]}"

        # Check if count is a valid number
        if ! [[ "$count" =~ ^[0-9]+$ ]]; then
            echo "Error: Invalid count at index $i, count is $count."
            return 0
        fi

        if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            value=0
            # echo "Invalid value at index $i. Setting it to 0."
            return 0
        fi

        # Calculate the sum for each attribute
        local sum=$(bc <<< "scale=0; $count * $value")
        total_sum=$(bc <<< "scale=0; $total_sum + $sum" )
        
        # Increment total count
        total_count=$(( total_count + count ))
    done

    # Check if total_count is 0 to avoid division by zero
    if [ "$total_count" -eq 0 ]; then
        echo "Error: Total count is zero.###############################################################"
        return 0
    fi

    # Calculate the arithmetic mean
    local arithmetic_mean=$(bc <<< "scale=0; $total_sum / $total_count")
    echo "$arithmetic_mean"
}



function get_standard_deviation() {
    local -a arr=("${@:2}")
    local n=${#arr[@]}
    local mean=$1
    

    local sum_diff_sq=0
    for num in "${arr[@]}"; do
        local diff=$(bc <<< "scale=0; ($num - $mean)^2")
        sum_diff_sq=$(bc <<< "scale=0; $sum_diff_sq + $diff")
    done
    standard_deviation=$(bc <<< "scale=0; sqrt($sum_diff_sq / ($n - 1))")
    
    echo "$standard_deviation"
}

function print_overall_results() {

    local -n data=$1
    local exp_name=$2
    local scheme_name=$3
    local exp_num=$4
    local output_file="${exp_name}_results.csv"

    local workload=$(echo "$exp_name" | grep -oP '(?<=workload_)[^-\s]+')
    local client=$(echo "$exp_name" | grep -oP '(?<=-clients-)\d+')
    local distribution=$(echo "$exp_name" | grep -oP '(?<=-dist_)[^-]+')
    local consistency=$(echo "$exp_name" | grep -oP '(?<=-consistency_)[^-]+')
    local rf=$(echo "$exp_name" | grep -oP '(?<=-rf_)\d+')
    local valueSize=$(echo "$exp_name" | grep -oP '(?<=-valueSize_)\d+')




    # sort the rounds
    local -a rounds=()
    for round_key in "${!data[@]}"; do
        if [[ $round_key == *",round" ]]; then
            rounds+=("${data[$round_key]}")
        fi
    done
    IFS=$'\n' sorted_rounds=($(sort <<<"${rounds[*]}"))
    unset IFS

    echo "Printing the sorted rounds ${sorted_rounds[@]}"

    # clean the output file
    > "$output_file"

    echo -n "Metrics," >> "$output_file"
    echo -n "Mean," >> "$output_file"
    echo -n "Student's t Error," >> "$output_file"
    echo -n "Lower Bound," >> "$output_file"
    echo -n "Upper Bound," >> "$output_file"
    echo "" >> "$output_file"


    OVERALL_KEYS=("average_read_latency" "median_read_latency" "tail_read_latency_75th" "tail_read_latency_95th" "tail_read_latency_99th" "tail_read_latency_999th" "average_update_latency" "tail_update_latency_99th" "overall_runtime" "overall_throughput" "average_user_time" "average_sys_time" "average_disk_read_io" "average_disk_write_io" "average_local_read_latency" "average_coordinator_read_latency" "average_local_write_latency" "average_local_scan_latency" "average_coordinator_scan_latency" "replica_selection_cost" "read_network_cost" "average_scan_latency" "tail_scan_latency_99th" "average_insert_latency" "tail_insert_latency_99th" "average_coordinator_read_time" "average_local_read_time" "average_write_memtable_time" "average_write_wal_time" "average_flush_time" "average_compaction_time" "average_read_cache_time" "average_read_memtable_time" "average_read_sstable_time" "average_read_two_layer_log_time" "average_merge_sort_time" "overall_latency_average" "overall_latency_50th" "overall_latency_75th" "overall_latency_95th" "overall_latency_99th" "overall_latency_999th" "average_overall_disk_io" "average_overall_network_io" "average_overall_cpu_time" "average_read_wait_time" "cov_coordinator_read_time" "std_local_read_time" "average_selection_time" "avg_mem_size" "average_coordinator_write_latency")

    # calculate the student t distribution for 95% confidence interval
    for key in "${OVERALL_KEYS[@]}"; do
        metrics=()
        for round in "${sorted_rounds[@]}"; do
            # echo "Round: $round, Key: $key, value: ${data[$round,$key]}"
            metrics+=("${data[$round,$key]}")
        done

        mean=$(echo "scale=2; ($(IFS=+; echo "(${metrics[*]})") / ${#metrics[@]})" | bc)
        # echo "Mean for $key: $mean"
        standard_deviation=$(get_standard_deviation "${metrics[@]}" $mean)
        # echo "Standard Deviation for $key: $standard_deviation"
        standard_error=$(echo "scale=2; ${standard_deviation} / sqrt(${#metrics[@]})" | bc)
        # echo "Standard Error for $key: $standard_error"


        degrees_of_freedom=$((${#metrics[@]} - 1))
        # echo "Degrees of Freedom for $key: $degrees_of_freedom"
        t_distribution=$(Rscript -e "qt(0.975, df=$degrees_of_freedom)" | awk '{print $2}')
        # echo "T Distribution for $key: $t_distribution"
        t_error=$(echo "scale=2; $t_distribution * $standard_error" | bc)
        # echo "T Error for $key: $t_error"


        lower_bound=$(echo "scale=2; $mean - ${t_error}" | bc)
        # echo "Lower Bound for $key: $lower_bound"
        upper_bound=$(echo "scale=2; $mean + ${t_error}" | bc)
        # echo "Upper Bound for $key: $upper_bound"

        echo -n "$key," >> "$output_file"
        echo -n "$mean," >> "$output_file"
        echo -n "$t_error," >> "$output_file"
        echo -n "$lower_bound," >> "$output_file"
        echo -n "$upper_bound," >> "$output_file"

        echo "" >> "$output_file"

        output_to_res_file $key $scheme_name $workload $exp_num $consistency $distribution $rf $valueSize $client $mean $t_error

    done
}


function output_to_res_file {
    local key=$1
    local scheme_name=$2
    local workload=$3
    local exp_num=$4
    local consistency=$5
    local distribution=$6
    local rf=$7
    local valueSize=$8
    local client=$9
    shift 9
    local mean=$1
    local t_error=$2

    echo "Key: $key, Scheme: $scheme_name, Workload: $workload, Exp Num: $exp_num, Consistency: $consistency, Distribution: $distribution, RF: $rf, Value Size: $valueSize, Client: $client, Mean: $mean, T Error: $t_error"

    if [ "$exp_num" = "ycsb" ]; then
        if [ $key == "overall_throughput" ]; then
            echo -n "" >> "$OVERALL_THPT_RES"
            echo -n "$scheme_name    " >> "$OVERALL_THPT_RES"
            echo -n "$workload    " >> "$OVERALL_THPT_RES"
            echo -n "$mean    " >> "$OVERALL_THPT_RES"
            echo -n "$t_error    " >> "$OVERALL_THPT_RES"
            echo "" >> "$OVERALL_THPT_RES"
        elif [ $key == "overall_latency_50th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$workload       " >> "$OVERALL_LATENCY_RES"
            echo -n "50    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_75th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$workload       " >> "$OVERALL_LATENCY_RES"
            echo -n "75    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_95th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$workload       " >> "$OVERALL_LATENCY_RES"
            echo -n "95    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$workload       " >> "$OVERALL_LATENCY_RES"
            echo -n "99    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_999th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$workload       " >> "$OVERALL_LATENCY_RES"
            echo -n "999    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "average_overall_cpu_time" ]; then
            echo -n "" >> "$OVERALL_RESOURCE_RES"
            echo -n "$scheme_name    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$workload       " >> "$OVERALL_RESOURCE_RES"
            echo -n "CPU    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$mean    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$t_error    " >> "$OVERALL_RESOURCE_RES"
            echo "" >> "$OVERALL_RESOURCE_RES"
        elif [ $key == "average_overall_disk_io" ]; then
            echo -n "" >> "$OVERALL_RESOURCE_RES"
            echo -n "$scheme_name    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$workload       " >> "$OVERALL_RESOURCE_RES"
            echo -n "Disk    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$mean    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$t_error    " >> "$OVERALL_RESOURCE_RES"
            echo "" >> "$OVERALL_RESOURCE_RES"
        elif [ $key == "average_overall_network_io" ]; then
            echo -n "" >> "$OVERALL_RESOURCE_RES"
            echo -n "$scheme_name    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$workload       " >> "$OVERALL_RESOURCE_RES"
            echo -n "Network    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$mean    " >> "$OVERALL_RESOURCE_RES"
            echo -n "$t_error    " >> "$OVERALL_RESOURCE_RES"
            echo "" >> "$OVERALL_RESOURCE_RES"
        fi
    elif [ "$exp_num" = "consistency" ]; then
        if [ $key == "overall_throughput" ]; then
            echo -n "" >> "$OVERALL_THPT_RES"
            echo -n "$scheme_name    " >> "$OVERALL_THPT_RES"
            echo -n "$consistency    " >> "$OVERALL_THPT_RES"
            echo -n "$mean    " >> "$OVERALL_THPT_RES"
            echo -n "$t_error    " >> "$OVERALL_THPT_RES"
            echo "" >> "$OVERALL_THPT_RES"
        elif [ $key == "overall_latency_50th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$consistency       " >> "$OVERALL_LATENCY_RES"
            echo -n "50    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_75th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$consistency       " >> "$OVERALL_LATENCY_RES"
            echo -n "75    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_95th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$consistency       " >> "$OVERALL_LATENCY_RES"
            echo -n "95    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$consistency       " >> "$OVERALL_LATENCY_RES"
            echo -n "99    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_999th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$consistency       " >> "$OVERALL_LATENCY_RES"
            echo -n "999    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        fi
    
    elif [ "$exp_num" = "distribution" ]; then
        if [ $key == "overall_throughput" ]; then
            echo -n "" >> "$OVERALL_THPT_RES"
            echo -n "$scheme_name    " >> "$OVERALL_THPT_RES"
            echo -n "$distribution    " >> "$OVERALL_THPT_RES"
            echo -n "$mean    " >> "$OVERALL_THPT_RES"
            echo -n "$t_error    " >> "$OVERALL_THPT_RES"
            echo "" >> "$OVERALL_THPT_RES"
        elif [ $key == "overall_latency_50th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$distribution       " >> "$OVERALL_LATENCY_RES"
            echo -n "50    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_75th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$distribution       " >> "$OVERALL_LATENCY_RES"
            echo -n "75    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_95th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$distribution       " >> "$OVERALL_LATENCY_RES"
            echo -n "95    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$distribution       " >> "$OVERALL_LATENCY_RES"
            echo -n "99    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_999th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$distribution       " >> "$OVERALL_LATENCY_RES"
            echo -n "999    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        fi
    elif [ "$exp_num" = "rf" ]; then
        if [ $key == "overall_throughput" ]; then
            echo -n "" >> "$OVERALL_THPT_RES"
            echo -n "$scheme_name    " >> "$OVERALL_THPT_RES"
            echo -n "$rf    " >> "$OVERALL_THPT_RES"
            echo -n "$mean    " >> "$OVERALL_THPT_RES"
            echo -n "$t_error    " >> "$OVERALL_THPT_RES"
            echo "" >> "$OVERALL_THPT_RES"
        elif [ $key == "overall_latency_50th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$rf       " >> "$OVERALL_LATENCY_RES"
            echo -n "50    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_75th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$rf       " >> "$OVERALL_LATENCY_RES"
            echo -n "75    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_95th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$rf       " >> "$OVERALL_LATENCY_RES"
            echo -n "95    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$rf       " >> "$OVERALL_LATENCY_RES"
            echo -n "99    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_999th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$rf       " >> "$OVERALL_LATENCY_RES"
            echo -n "999    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        fi
    elif [ "$exp_num" = "valueSize" ]; then
        if [ $key == "overall_throughput" ]; then
            echo -n "" >> "$OVERALL_THPT_RES"
            echo -n "$scheme_name    " >> "$OVERALL_THPT_RES"
            echo -n "$valueSize    " >> "$OVERALL_THPT_RES"
            echo -n "$mean    " >> "$OVERALL_THPT_RES"
            echo -n "$t_error    " >> "$OVERALL_THPT_RES"
            echo "" >> "$OVERALL_THPT_RES"
        elif [ $key == "overall_latency_50th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$valueSize       " >> "$OVERALL_LATENCY_RES"
            echo -n "50    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_75th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$valueSize       " >> "$OVERALL_LATENCY_RES"
            echo -n "75    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_95th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$valueSize       " >> "$OVERALL_LATENCY_RES"
            echo -n "95    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$valueSize       " >> "$OVERALL_LATENCY_RES"
            echo -n "99    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_999th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$valueSize       " >> "$OVERALL_LATENCY_RES"
            echo -n "999    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        fi
    elif [ "$exp_num" = "client" ]; then
                if [ $key == "overall_throughput" ]; then
            echo -n "" >> "$OVERALL_THPT_RES"
            echo -n "$scheme_name    " >> "$OVERALL_THPT_RES"
            echo -n "$client    " >> "$OVERALL_THPT_RES"
            echo -n "$mean    " >> "$OVERALL_THPT_RES"
            echo -n "$t_error    " >> "$OVERALL_THPT_RES"
            echo "" >> "$OVERALL_THPT_RES"
        elif [ $key == "overall_latency_50th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$client       " >> "$OVERALL_LATENCY_RES"
            echo -n "50    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_75th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$client       " >> "$OVERALL_LATENCY_RES"
            echo -n "75    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_95th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$client       " >> "$OVERALL_LATENCY_RES"
            echo -n "95    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$client       " >> "$OVERALL_LATENCY_RES"
            echo -n "99    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "overall_latency_999th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "$client       " >> "$OVERALL_LATENCY_RES"
            echo -n "999    " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        fi
    elif [ "$exp_num" = "zippydb" ]; then
        if [ $key == "average_read_latency" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "average_read       " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "tail_read_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "tail_read_latency_99th       " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "average_update_latency" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "average_update_latency       " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "tail_update_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "tail_update_latency_99th       " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "average_scan_latency" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "average_scan_latency       " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        elif [ $key == "tail_scan_latency_99th" ]; then
            echo -n "" >> "$OVERALL_LATENCY_RES"
            echo -n "$scheme_name    " >> "$OVERALL_LATENCY_RES"
            echo -n "tail_scan_latency_99th       " >> "$OVERALL_LATENCY_RES"
            echo -n "$mean    " >> "$OVERALL_LATENCY_RES"
            echo -n "$t_error    " >> "$OVERALL_LATENCY_RES"
            echo "" >> "$OVERALL_LATENCY_RES"
        fi
    fi

     
}

# print the round results
function print_round_results() {
    local -n data=$1
    local round=$2
    local exp_dir=$3
    local output_file="${exp_dir}/${round}_results.csv"

    # sort the nodes
    local -a nodes=()
    for node_key in "${!data[@]}"; do
        if [[ $node_key == *",node_name" ]]; then
            nodes+=("${data[$node_key]}")
        fi
    done
    IFS=$'\n' sorted_nodes=($(sort <<<"${nodes[*]}"))
    unset IFS

    # clean the output file
    > "$output_file"

    # echo -n "Data Type," >> "$output_file"
    for node in "${sorted_nodes[@]}"; do
        echo -n "$node," >> "$output_file"
    done
    echo "" >> "$output_file"
    OUTPUT_KEY_OF_EACH_NODE=("node_name" "uptime" "user_time" "sys_time" "disk_read_io" "disk_write_io" "network_recv_io" "network_send_io" "local_read_count" "local_read_latency" "coordinator_read_count" "coordinator_read_latency" "local_write_count" "local_write_latency" "coordinator_write_count" "coordinator_write_latency" "local_scan_count" "local_scan_latency" "coordinator_scan_count" "coordinator_scan_latency" "coordinator_read_time" "local_read_time" "write_memtable_time" "write_wal_time" "flush_time" "compaction_time" "read_cache_time" "read_memtable_time" "read_sstable_time" "read_two_layer_log_time" "merge_sort_time" "forwarded_requests" "overall_cpu_time" "overall_disk_io" "overall_network_io" "read_wait_time" "selection_time" "mem_size" "read_net_io" "write_net_io")

    for key in "${OUTPUT_KEY_OF_EACH_NODE[@]}"; do
        echo -n "$key," >> "$output_file"
        for node in "${sorted_nodes[@]}"; do
            echo -n "${data[$node,$key]}," >> "$output_file"
        done
        echo "" >> "$output_file"
    done

    echo -n "Average Read Latency (us)," >> "$output_file"
    echo -n "${data[average_read_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Local Read Latency (us)," >> "$output_file"
    echo -n "${data[average_local_read_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Coordinator Read Latency (us)," >> "$output_file"
    echo -n "${data[average_coordinator_read_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Local Write Latency (us)," >> "$output_file"
    echo -n "${data[average_local_write_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Local Scan Latency (us)," >> "$output_file"
    echo -n "${data[average_local_scan_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Coordinator Scan Latency (us)," >> "$output_file"
    echo -n "${data[average_coordinator_scan_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Replica Selection Cost (us)," >> "$output_file"
    echo -n "${data[replica_selection_cost]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Read Network Cost (us)," >> "$output_file"
    echo -n "${data[read_network_cost]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Median Read Latency (us)," >> "$output_file"
    echo -n "${data[median_read_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "75th Percentile Read Latency (us)," >> "$output_file"
    echo -n "${data[tail_read_latency_75th]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "95th Percentile Read Latency (us)," >> "$output_file"
    echo -n "${data[tail_read_latency_95th]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "99th Percentile Read Latency (us)," >> "$output_file"
    echo -n "${data[tail_read_latency_99th]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "999th Percentile Read Latency (us)," >> "$output_file"
    echo -n "${data[tail_read_latency_999th]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Update Latency (us)," >> "$output_file"
    echo -n "${data[average_update_latency]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "99th Percentile Update Latency (us)," >> "$output_file"
    echo -n "${data[tail_update_latency_99th]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Overall Runtime (ms)," >> "$output_file"
    echo -n "${data[overall_runtime]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Overall Throughput (ops/sec)," >> "$output_file"
    echo -n "${data[overall_throughput]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average User Time (s)," >> "$output_file"
    echo -n "${data[average_user_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average System Time (s)," >> "$output_file"
    echo -n "${data[average_sys_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Disk Read I/O (MiB)," >> "$output_file"
    echo -n "${data[average_disk_read_io]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Disk Write I/O (MiB)," >> "$output_file"
    echo -n "${data[average_disk_write_io]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Coordinator Read Time (us)," >> "$output_file"
    echo -n "${data[average_coordinator_read_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "CoV Coordinator Read Time," >> "$output_file"
    echo -n "${data[cov_coordinator_read_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Std local read time," >> "$output_file"
    echo -n "${data[std_local_read_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Local Read Time (us)," >> "$output_file"
    echo -n "${data[average_local_read_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Read Selection Time (us)," >> "$output_file"
    echo -n "${data[average_selection_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Write Memtable Time (us)," >> "$output_file"
    echo -n "${data[average_write_memtable_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Write WAL Time (us)," >> "$output_file"
    echo -n "${data[average_write_wal_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Flush Time (us)," >> "$output_file"
    echo -n "${data[average_flush_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Compaction Time (us)," >> "$output_file"
    echo -n "${data[average_compaction_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Read Cache Time (us)," >> "$output_file"
    echo -n "${data[average_read_cache_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Read Memtable Time (us)," >> "$output_file"
    echo -n "${data[average_read_memtable_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Read SSTable Time (us)," >> "$output_file"
    echo -n "${data[average_read_sstable_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Total forwarded requests," >> "$output_file"
    echo -n "${data[forward_requests_of_all_nodes]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Read Two Layer Log Time (us)," >> "$output_file"
    echo -n "${data[average_read_two_layer_log_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Merge Sort Time (us)," >> "$output_file"
    echo -n "${data[average_merge_sort_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Overall CPU Time (s)," >> "$output_file"
    echo -n "${data[average_overall_cpu_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Overall Disk I/O (MiB)," >> "$output_file"
    echo -n "${data[average_overall_disk_io]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Overall Network I/O (MiB)," >> "$output_file"
    echo -n "${data[average_overall_network_io]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Read Wait Time (us)," >> "$output_file"
    echo -n "${data[average_read_wait_time]}," >> "$output_file"
    echo "" >> "$output_file"
    echo -n "Average Memory Size (GiB)," >> "$output_file"
    echo -n "${data[average_mem_size]}," >> "$output_file"
    echo "" >> "$output_file"
    
}



function main {
    local main_dir=$1
    local exp_num=$2
    if [[ -z "$main_dir" ]]; then
        echo "Usage: $0 <directory> <exp>"
        exit 1
    fi

    process_directory "$main_dir" "$exp_num"
}

main "$1" "$2"
