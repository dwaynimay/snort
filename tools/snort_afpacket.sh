#!/bin/bash

echo "[*] Membersihkan aturan firewall lama..."
sudo iptables -F

echo "[*] Firewall SIAP. Menjalankan Snort sekarang..."
echo "[!] Tekan Ctrl+C untuk berhenti (Firewall akan tetap aktif sampai direstart/direset)"

# Command Snort (Disatukan dalam satu baris agar rapi)
# Perhatikan: Saya ganti --daq afpacket menjadi --daq nfq
sudo snort -c /usr/local/etc/snort/snort.lua \
--talos -Q --daq afpacket -i enp0s3\
--lua 'snort_ml_engine = { http_param_model = "/usr/local/etc/snort/models/models/MLP_Last_2/cicids_mlp_float32.tflite" }; snort_ml = { http_param_threshold = 0.5 }; trace = { modules = { snort_ml = {all =1 } } };' \
--lua 'alert_fast = { file = false }' \
-A alert_fast -s 65535 -k none