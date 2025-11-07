#!/bin/bash

# ===================================================================
# This script tests downloading files of various sizes using HTTP/2
# ===================================================================

SERVER="192.168.3.220"
PORT="4433"
INTERFACE="eth0"
OUTPUT_DIR="raw2_data"
OUTPUT_FILE="http2_file_test_results.csv"

#Test files on the server
FILE_SIZES_MB=(50 100 200 300 400 500 600 700 800 900 1000)

#Bandwidth limits to test
BANDWIDTHS=("50mbit" "100mbit" "200mbit" "300mbit" "400mbit" "500mbit" "600mbit" "700mbit" "800mbit" "900mbit" "1000mbit")
#Number of iterations for each test
ITERATIONS=5

#PIDSTAT settings
PIDSTAT_INTERVAL=0.05
CURL_BIN="/home/tumelo/opt/curl-quic/bin/curl"

#Create the output directory
mkdir -p $OUTPUT_DIR

#CSV header
echo "File Size,Bandwidth(mbit),Iteration,Download Time(s),Throughput(Mbps),CPU Usage(%)" > $OUTPUT_FILE

#TC and Helper Functions
#Set bandwidth limit using tc
set_bandwidth_limit() {
    local BANDWIDTH=$1
    echo "Setting bandwidth limit to $BANDWIDTH"
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
    sudo tc qdisc add dev $INTERFACE root tbf rate $BANDWIDTH burst 32kbit latency 400ms
}
reset_bandwidth_limit() {
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
}

#Main testing loop

for FILE_SIZE in "${FILE_SIZES_MB[@]}"; do
    FILE_NAME="file_${FILE_SIZE}MB.bin"
    #Calculate the file size in bits for throughput calculation
    #Size in MB * 1024 * 1024 bytes/MB * 8 bits/byte
    FILE_SIZE_BITS=$(echo "scale=0; ${FILE_SIZE} * 1048576 * 8" | bc)

    for BANDWIDTH in "${BANDWIDTHS[@]}"; do
        set_bandwidth_limit "$BANDWIDTH"
        echo "Testing HTTP/2 for ${FILE_NAME} at bandwidth ${BANDWIDTH}"
        for ((i=1; i<=ITERATIONS; i++)); do
            echo "Iteration $i: Downloading ${FILE_NAME}"
            #Measure start time
            START_TIME=$(date +%s.%N)
            # Start pidstat and write output to temp file
            #PIDSTAT_FILE="${OUTPUT_DIR}/pidstat_${FILE_SIZE}_${BANDWIDTH}_${i}.txt"
            
            #Run curl and capture PID
            $CURL_BIN -w "TOTAL_TIME:%{time_total}\n" -o /dev/null -k --http2 "https://${SERVER}:${PORT}/${FILE_NAME}" & CURL_PID=$!

            CPU_FILE="${OUTPUT_DIR}/cpu_${FILE_SIZE}_${BANDWIDTH}_${i}.json"
            #sleep 0.05
            python3 cpu_tracker.py $CURL_PID "$CPU_FILE" $PIDSTAT_INTERVAL & CPU_PID=$!
            sleep 0.1

            #sudo pidstat -u -p $CURL_PID $PIDSTAT_INTERVAL > "$PIDSTAT_FILE" 2>&1 &
            #PIDSTAT_PID=$!
            
          

            #Wait for curl to finish
            wait $CURL_PID 2>/dev/null

            #Run curl and capture PID
            #($CURL_BIN -w "TOTAL_TIME:%{time_total}\n" -o /dev/null -k --http2 "https://${SERVER}:${PORT}/${FILE_NAME}") & CURL_PID=$!
            #Measure end time
            END_TIME=$(date +%s.%N)
            #Stop monitoring
            sudo kill "$CPU_PID" 2>/dev/null
            wait "$CPU_PID" 2>/dev/null
            

            #Data extraction and calculations
            DOWNLOAD_TIME=$(echo "scale=4; $END_TIME - $START_TIME" | bc)
            #Throughput in Mbps: (FILE_SIZE_BITS / DOWNLOAD_TIME) / 1,000,000 (to convert to Mbps) 
            THROUGHPUT=$(echo "scale=2; ($FILE_SIZE_BITS / $DOWNLOAD_TIME) / 1000000" | bc)

            #Calculate average CPU usage from pidstat output
            #CPU_USER_AVG=$(awk '/^[0-9]/ {sum+=$7; n++} END {if (n>0) print sum/n; else print 0}' "$PIDSTAT_FILE")
            #CPU_SYS_AVG=$(awk '/^[0-9]/ {sum+=$8; n++} END {if (n>0) print sum/n; else print 0}' "$PIDSTAT_FILE")
            #CPU_USER_AVG=$(jq '.avg_cpu' "$CPU_FILE")
            if [[ -f "$CPU_FILE" ]]; then
                CPU_USER_AVG=$(jq '.avg_cpu' "$CPU_FILE")
            else
                CPU_USER_AVG=0.0
            fi


            #CPU_USER_AVG=$(awk '/^[[:space:]]*[0-9]/ {sum+=$7; n++} END {if (n>0) print sum/n; else print 0}' "$PIDSTAT_FILE")
            #CPU_SYS_AVG=$(awk '/^[[:space:]]*[0-9]/ {sum+=$8; n++} END {if (n>0) print sum/n; else print 0}' "$PIDSTAT_FILE")
 
            #Log results to CSV
            echo "${FILE_NAME},${BANDWIDTH},${i},${DOWNLOAD_TIME},${THROUGHPUT},${CPU_USER_AVG}" >> $OUTPUT_FILE

            #Cleanup temporary pidstat file
            rm -f "$CPU_FILE"
        done
    done
done
reset_bandwidth_limit
echo "Testing completed. Results saved to $OUTPUT_FILE"