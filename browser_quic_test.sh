#!/bin/bash

# ======================================================
# Browser QUIC File Download Performance Test Script
# ======================================================

SERVER="192.168.3.220"
PORT="4433"
INTERFACE="eth2"
BROWSER_BIN="/snap/bin/chromium"
OUTPUT_DIR="browser_quic_data"
PROFILE_DIR="/tmp/chrome-quic"
OUTPUT_FILE="browser_quic_file_test_results.csv"

#Test files on the server
#FILES=("file_50MB.bin" "file_100MB.bin" "file_200MB.bin" "file_300MB.bin""file_400MB.bin""file_500MB.bin""file_600MB.bin""file_700MB.bin""file_800MB.bin""file_900MB.bin""file_1GB.bin")
FILE_SIZES_MB=(50 100 200 300 400 500 600 700 800 900 1000)
#Bandwidth limits in Mbps
BANDWIDTHS=("50mbit" "100mbit" "200mbit" "300mbit" "400mbit" "500mbit" "600mbit" "700mbit" "800mbit" "900mbit" "1000mbit")
#Number of iterations for each test
ITERATIONS=5
#Pidstat interval in seconds
PIDSTAT_INTERVAL=0.05

#Create the output directory
mkdir -p $OUTPUT_DIR

#CSV Header
echo "File,Bandwidth,Iteration,Download Time(s),Load Time(s),Throughput(Mbps),CPU Usage(%)" > "$OUTPUT_FILE"

# Function to isolate the Network Service PID (Robust search using command-line arguments)
find_network_service_pid() {
    # Searches for the process that contains 'type=utility' AND 'network-service'
    # The 'head -n 1' ensures only one PID is returned
    ps aux | grep 'type=utility' | grep 'network-service' | grep -v grep | awk '{print $2}' | head -n 1
}

set_bandwidth_limit() {
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
    sudo tc qdisc add dev $INTERFACE root tbf rate $1 burst 32kbit latency 400ms
}

reset_bandwidth_limit() {
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
}

for FILE_SIZE in "${FILE_SIZES_MB[@]}"; do 
    FILE_NAME="file_${FILE_SIZE}MB.bin"
    FILE_SIZE_BITS=$(echo "$FILE_SIZE * 1048576 * 8" | bc)
    for BANDWIDTH in "${BANDWIDTHS[@]}"; do 
        set_bandwidth_limit "$BANDWIDTH"
        echo "Downloading ${FILE_NAME} via QUIC at ${BANDWIDTH}"
        for ((i=1; i<=ITERATIONS; i++)); do
            rm -rf "/tmp/chrome-quic_$i"
            echo "Iteration $i: Downloading ${FILE_NAME}"
            START_TIME=$(date +%s.%N)
            timeout 10s $BROWSER_BIN --headless --disable-gpu --enable-quic --origin-to-force-quic-on=${SERVER}:${PORT} --no-sandbox --quic-version=h3-29 --enable-logging --log-level=0 --v=1 --enable-precise-memory-info --enable-benchmarking --enable-net-benchmarking --user-data-dir=/tmp/chrome-quic_$i --allow-insecure-localhost --ignore-certificate-errors "https://${SERVER}:${PORT}/${FILE_NAME}" > "${OUTPUT_DIR}/perf_${FILE_SIZE}_${BANDWIDTH}_${i}.json" 2>&1 &
            BROWSER_PID=$!
            # Use unique temp file path in the output directory
            #PIDSTAT_TEMP_FILE="${OUTPUT_DIR}/pidstat_temp_${i}.txt"

            # CRITICAL CLEANUP BEFORE LAUNCH: Removes the singleton lock from previous crashes
            #rm -rf "$PROFILE_DIR"
            
            #Start browser with HTTP/2 settings
            #($BROWSER_BIN --headless --disable-gpu --enable-quic --no-sandbox --quic-version=h3 --enable-logging --log-level=0 --v=1 --enable-precise-memory-info --enable-benchmarking --enable-net-benchmarking --user-data-dir=/tmp/chrome-quic_$i --ignore-certificate-errors "https://${SERVER}:${PORT}/${FILE_NAME}" > perf_log.json 2>&1 &) & BROWSER_PID=$!
            #sleep 1
            #Monitor CPU usage of the main browser process
            #pidstat -T TASK -u -h -r -p "$BROWSER_PID" $PIDSTAT_INTERVAL > "$PIDSTAT_TEMP_FILE" 2>/dev/null & PIDSTAT_PID=$!
            CPU_JSON_FILE="${OUTPUT_DIR}/cpu_${FILE_SIZE}_${BANDWIDTH}_${i}.json"
            sleep 0.1
            #Monitor CPU usage
            python3 cpu_tracker.py $BROWSER_PID "$CPU_JSON_FILE" $PIDSTAT_INTERVAL & CPU_PID=$!
          
            wait $BROWSER_PID 2>/dev/null
            END_TIME=$(date +%s.%N)

            sudo kill $CPU_PID 2>/dev/null
            wait "$CPU_PID" 2>/dev/null
          
            DURATION=$(echo "scale=4; $END_TIME - $START_TIME" | bc)
            THROUGHPUT=$(echo "scale=2; ($FILE_SIZE_BITS / $DURATION) / 1000000" | bc)
            #Extract CPU usage (using reliable awk indices)
             if [[ -s "$CPU_JSON_FILE" ]]; then
                CPU_USER_AVG=$(jq '.avg_cpu' "$CPU_JSON_FILE" 2>/dev/null || echo 0.0)
            else 
                CPU_USER_AVG=0.0
            fi

            #CPU_AVG=$(grep "Average" "$PIDSTAT_TEMP_FILE" | tail -n1)

            #if [ -n "$CPU_AVG" ]; then 
                # Extract CPU usage
                #CPU_USER_AVG=$(echo "$CPU_AVG" | awk '{print $4}')
                #CPU_SYS_AVG=$(echo "$CPU_AVG" | awk '{print $5}')
            #else
                #CPU_USER_AVG=0.0
                #CPU_SYS_AVG=0.0
            #fi
            # Extract page load time from Chrome log (approximation)
            LOAD_TIME=$(grep -oP '"loadEventEnd":\K[0-9]+' perf_log.json | tail -1)
            LSTART_TIME=$(grep -oP '"navigationStart":\K[0-9]+' perf_log.json | tail -1)

            if [[ -n "$LOAD_TIME" && -n "$LSTART_TIME" ]]; then
                LOAD_SEC=$(echo "scale=3; ($LOAD_TIME - $LSTART_TIME)/1000" | bc)
            else
                LOAD_SEC=$DURATION
            fi
            echo "${FILE_NAME},${BANDWIDTH},${i},${DURATION},${LOAD_SEC},${THROUGHPUT},${CPU_USER_AVG},${CPU_SYS_AVG}" >> "$OUTPUT_FILE"
            #rm -f "$PIDSTAT_TEMP_FILE" perf_log.json
            rm -rf "/tmp/chrome-quic_$i"
        done
    done
done
reset_bandwidth_limit
echo "QUIC browser test completed. Results saved to $OUTPUT_FILE"

#For HTTP/2 only: chromium --disable-quic --user-data-dir=/tmp/chrome-http2 --ignore-certificate-errors &

#For QUIC only: chromium --enable-quic --quic-version=h3 --user-data-dir=/tmp/chrome-quic --ignore-certificate-errors &
