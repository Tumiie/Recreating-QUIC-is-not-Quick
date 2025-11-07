import pandas as pd 
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
import os

# Configuration
DATASETS = { "chrome_http2": "browser_http2_file_test_results.csv", "chrome_quic": "browser_quic_file_test_results.csv" }
OUTPUT_DIR = "chrome_plots"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Helper Functions
def clean_file_size(x):
    #Convert file_50MB.bin to 50
    try:
        return int(x.split("_")[1].replace("MB.bin", ""))
    except Exception:
        return np.nan

def clean_bandwidth(x):
    #Convert 100mbit to 100
    try:
        return int(x.replace("mbit", ""))
    except Exception:
        return np.nan

def load_and_prepare(file_path, label):
    df = pd.read_csv(file_path)
    df["File_MB"] = df["File"].apply(clean_file_size)
    df["Bandwidth_Mbps"] = df["Bandwidth"].apply(clean_bandwidth)
    df["CPU Usage"] = df["CPU Usage(%)"].astype(float)
    df["Protocol"] = label
    df["Throughput(Mbps)"] = df["Throughput(Mbps)"].astype(float)
    df["Page Load Time(s)"] = df["Load Time(s)"]
    return df

# === Load all datasets ===
frames = []
for label, path in DATASETS.items():
    try:
        frames.append(load_and_prepare(path, label))
        print(f"Load {label} from {path}")
    except Exception as e:
        print(f"Could not read {path}: {e}")
df_all = pd.concat(frames, ignore_index=True)

sns.set(style="whitegrid", font_scale=1.2)

# 1. Throughput vs File Size
plt.figure(figsize=(10,6))
sns.lineplot(data=df_all, x="File_MB", y="Throughput(Mbps)",
             hue="Protocol", errorbar=("sd"), marker="o", linewidth=2)
plt.title("Throughput vs File Size (Chrome)")
plt.xlabel("File Size (MB)")
plt.ylabel("Throughput (Mbps)")
plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}/chrome_throughput_vs_filesize.png", dpi=300)
plt.show()
plt.close()

# 2. CPU Boxplot for 1GB
cpu_df = df_all[df_all["File_MB"] == 1000]
plt.figure(figsize=(8,6))
sns.boxplot(data=cpu_df, x="Protocol", y="CPU Usage", palette="pastel")
plt.title("CPU Usage for 1 GB File (Chrome)")
plt.ylabel("CPU Usage (%)")
plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}/chrome_cpu_usage_1GB_boxplot.png", dpi=300)
plt.show()
plt.close()

# 3. Throughput vs Bandwidth
plt.figure(figsize=(10,6))
sns.lineplot(data=df_all, x="Bandwidth_Mbps", y="Throughput(Mbps)",
             hue="Protocol", errorbar=("sd"), marker="o", linewidth=2)
plt.title("Actual Throughput vs Available Bandwidth (Chrome)")
plt.xlabel("Available Bandwidth (Mbps)")
plt.ylabel("Actual Throughput (Mbps)")
plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}/chrome_actual_throughput_vs_bandwidth.png", dpi=300)
plt.show()
plt.close()

plt.figure(figsize=(10,6))
sns.lineplot(
    data=df_all,
    x="Bandwidth_Mbps",
    y="Throughput(Mbps)",
    hue="Protocol",
    marker="o"
)
plt.yscale("log")
plt.title("Log Scale: Throughput vs Bandwidth (Chrome)")
plt.xlabel("Available Bandwidth (Mbps)")
plt.ylabel("Throughput (Mbps, Log Scale)")
plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}/chrome_log_throughput_vs_bandwidth.png", dpi=300)
plt.show()
plt.close()

# 4. CPU Usage vs Bandwidth
plt.figure(figsize=(10,6))
sns.lineplot(data=df_all, x="Bandwidth_Mbps", y="CPU Usage",
             hue="Protocol", errorbar=("sd"), marker="o", linewidth=2)
plt.title("CPU Usage vs Available Bandwidth (Chrome)")
plt.xlabel("Available Bandwidth (Mbps)")
plt.ylabel("CPU Usage (%)")
plt.tight_layout()
plt.savefig(f"{OUTPUT_DIR}/chrome_cpu_vs_bandwidth.png", dpi=300)
plt.show()
plt.close()

print("All Chrome performance plots saved in:", OUTPUT_DIR)

