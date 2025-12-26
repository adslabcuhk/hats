#!/bin/bash

# 定义数组来存储每分钟的总 Thpt
totalReadThpt=()
totalWriteThpt=()
totalFlushThpt=()
totalCompactionThpt=()

process_measurement_file() {
    local metricFile=$1
    local lineIndex=0 

    echo "Processing file: $metricFile"

    while IFS= read -r line || [[ -n "$line" ]]; do
        readThpt=$(echo "$line" | grep -oP 'Read Thpt: \K[0-9.]+')
        writeThpt=$(echo "$line" | grep -oP 'Write Thpt: \K[0-9.]+')
        flushThpt=$(echo "$line" | grep -oP 'Flush Thpt: \K[0-9.]+')
        compactionThpt=$(echo "$line" | grep -oP 'Compaction Thpt: \K[0-9.]+')

        if [[ -z "$readThpt" || -z "$writeThpt" || -z "$flushThpt" || -z "$compactionThpt" ]]; then
            echo "Skipping empty or malformed line: $line"
            continue
        fi

        echo "Extracted -> Read: $readThpt, Write: $writeThpt, Flush: $flushThpt, Compaction: $compactionThpt"

        totalReadThpt[$lineIndex]=$(echo "${totalReadThpt[$lineIndex]:-0} + $readThpt" | bc)
        totalWriteThpt[$lineIndex]=$(echo "${totalWriteThpt[$lineIndex]:-0} + $writeThpt" | bc)
        totalFlushThpt[$lineIndex]=$(echo "${totalFlushThpt[$lineIndex]:-0} + $flushThpt" | bc)
        totalCompactionThpt[$lineIndex]=$(echo "${totalCompactionThpt[$lineIndex]:-0} + $compactionThpt" | bc)

        echo "Accumulated -> Read: ${totalReadThpt[$lineIndex]}, Write: ${totalWriteThpt[$lineIndex]}, Flush: ${totalFlushThpt[$lineIndex]}, Compaction: ${totalCompactionThpt[$lineIndex]}"

        lineIndex=$((lineIndex + 1))
    done < "$metricFile"
}

process_directory() {
    local directory=$1
    for metricFile in $(find "$directory" -type f -name "measurement.txt"); do
        process_measurement_file "$metricFile"
    done
}

if [ -z "$1" ]; then
    echo "Usage: $0 /path/to/round_1"
    exit 1
fi

process_directory "$1"

if [ ${#totalReadThpt[@]} -eq 0 ]; then
    echo "No data was processed. Please check if measurement.txt files are correctly read."
    exit 1
fi

outputFile="aggregated_thpt_formatted.txt"
echo "x type y" > "$outputFile"
for i in "${!totalReadThpt[@]}"; do
    echo "$((i+1)) Read ${totalReadThpt[$i]}" >> "$outputFile"
    echo "$((i+1)) Write ${totalWriteThpt[$i]}" >> "$outputFile"
    echo "$((i+1)) Flush ${totalFlushThpt[$i]}" >> "$outputFile"
    echo "$((i+1)) Compaction ${totalCompactionThpt[$i]}" >> "$outputFile"
done

echo "Aggregation completed. Results saved to $outputFile"
