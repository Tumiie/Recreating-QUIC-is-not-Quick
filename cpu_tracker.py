import psutil
import json
import requests
import time
import logging
import sys
import os

def track_cpu(pid, out_file, interval=0.05):
    cpu_samples = []

    try:
        p = psutil.Process(pid)
    except psutil.NoSuchProcess:
        # Write dummy file
        with open(out_file, "w") as f:
            json.dump({"avg_cpu": 0, "samples": []}, f)
        #print("ERROR: Process does not exist.")
        return

    #cpu_samples = []

    # Prime the CPU counters
    p.cpu_percent(interval=None)

    while True:
        try:
            cpu_val = p.cpu_percent(interval=interval)
            for child in p.children(recursive=True):
                try:
                    cpu_val += child.cpu_percent(interval=0)
                except psutil.NoSuchProcess:
                    pass

            cpu_samples.append(cpu_val)
        except psutil.NoSuchProcess:
            break

    if len(cpu_samples) == 0:
        avg_cpu = 0.0
    else:
        avg_cpu = sum(cpu_samples) / len(cpu_samples)

    # Save result
    with open(out_file, "w") as f:
        json.dump({
            "pid": pid,
            "avg_cpu": avg_cpu,
            "samples": cpu_samples
        }, f)

if __name__ == "__main__":
    pid = int(sys.argv[1])
    out_file = sys.argv[2]
    interval = float(sys.argv[3])
    track_cpu(pid, out_file, interval)