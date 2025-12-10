#!/bin/bash

# Nama file log akan menyertakan tanggal saat ini
LOGFILE="hardware_log_$(date +%Y%m%d_%H%M%S).txt"

# Mencetak header ke file log
echo "Timestamp | CPU_Idle(%) | RAM_Free(MB) | Disk_r(kB/s) | Disk_w(kB/s) | NET_RX(kB/s) | NET_TX(kB/s)" > "$LOGFILE"

# Mencetak header ke terminal (optional, agar Anda tahu logging sudah mulai)
echo "Logging hardware stats every 1 second to: $LOGFILE"
echo "---"
echo "Timestamp | CPU_Idle(%) | RAM_Free(MB) | Disk_r(kB/s) | Disk_w(kB/s) | NET_RX(kB/s) | NET_TX(kB/s)"

# Loop utama untuk mengumpulkan data setiap detik
while true; do
  TS=$(date +%H:%M:%S)
  
  # Ambil statistik CPU dan RAM dari vmstat
  VMSTAT_OUT=$(vmstat 1 2 | tail -1)
  CPU_IDLE=$(echo $VMSTAT_OUT | awk '{print $15}')
  RAM_FREE_KB=$(echo $VMSTAT_OUT | awk '{print $4}')
  
  # Konversi RAM Free dari kB ke MB (dibulatkan 1 desimal)
  RAM_FREE_MB=$(echo "scale=1; $RAM_FREE_KB / 1024" | bc 2>/dev/null || echo "N/A")

  # Ambil total Disk Read/Write dari iostat (rata-rata keseluruhan)
  # Gunakan kolom 3 (r/s) dan 4 (w/s) dari laporan iostat -k
  DISK_STATS=$(iostat -d -k 1 2 | awk '/avg-cpu/ {next} /Device/ {next} NF>1 {print $3, $4}' | tail -1)
  DISK_R=$(echo $DISK_STATS | awk '{print $1}')
  DISK_W=$(echo $DISK_STATS | awk '{print $2}')
  
  # Ambil statistik Network dari sar
  # Perlu menjalankan sar secara terpisah karena intervalnya hanya 1 detik
  # rxkB/s dan txkB/s (kolom $5 dan $6 dari baris Average)
  NET_STATS=$(sar -n DEV 1 1 | awk '/Average:/ && $2!="IFACE" {print $5, $6}' | tail -1)
  NET_RX=$(echo $NET_STATS | awk '{print $1}')
  NET_TX=$(echo $NET_STATS | awk '{print $2}')

  # Cetak output ke terminal dan ke file log
  OUTPUT_LINE="$TS | $CPU_IDLE | $RAM_FREE_MB | $DISK_R | $DISK_W | $NET_RX | $NET_TX"
  echo "$OUTPUT_LINE" | tee -a "$LOGFILE" # tee mencetak ke terminal dan menambahkan ke file

  # Jeda 1 detik
  sleep 1 
done