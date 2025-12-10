#!/usr/bin/env bash

# Interval pengambilan data (detik)
INTERVAL=1

# Nama file log CSV dengan timestamp
LOGFILE="hardware_log_$(date +%Y%m%d_%H%M%S).csv"

# Asumsi ukuran sektor disk (byte) - mayoritas 512
SECTOR_SIZE=512

# Tulis header CSV
echo "timestamp,cpu_idle_pct,ram_available_mb,disk_read_kbs,disk_write_kbs,net_rx_kbs,net_tx_kbs" > "$LOGFILE"

echo "Logging hardware stats setiap ${INTERVAL}s ke file: $LOGFILE"
echo "Tekan Ctrl+C untuk berhenti."
echo "Kolom: timestamp,cpu_idle_pct,ram_available_mb,disk_read_kbs,disk_write_kbs,net_rx_kbs,net_tx_kbs"

# Trap agar ada pesan saat keluar
trap 'echo; echo "Stop logging. Log tersimpan di $LOGFILE"; exit 0' INT

# --- Fungsi bantu ---

get_cpu_times() {
  # Baca baris pertama 'cpu' dari /proc/stat
  # Format: cpu  user nice system idle iowait irq softirq steal guest guest_nice
  read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat

  # Total waktu (semua state)
  local total=$((user + nice + system + idle + iowait + irq + softirq + steal))

  echo "$idle $total"
}

get_ram_available_mb() {
  # Kalau MemAvailable ada, pakai itu (lebih realistik)
  if grep -q "MemAvailable:" /proc/meminfo 2>/dev/null; then
    awk '/MemAvailable:/ {printf "%.2f", $2/1024}' /proc/meminfo
  else
    # Fallback: free + buffers + cached
    awk '
      /MemFree:/  {free=$2}
      /Buffers:/  {buf=$2}
      /^Cached:/  {cache=$2}
      END {printf "%.2f", (free+buf+cache)/1024}
    ' /proc/meminfo
  fi
}

get_disk_sectors() {
  # Sum sektor read & write semua device kecuali loop, ram, fd
  awk '
    $3 !~ /^(loop|ram|fd)/ {
      read_sectors  += $6;
      write_sectors += $10;
    }
    END {print read_sectors, write_sectors}
  ' /proc/diskstats
}

get_net_bytes() {
  # Sum RX/TX bytes semua interface kecuali lo (loopback)
  awk '
    NR > 2 {
      gsub(":", "", $1);
      iface=$1;
      if (iface != "lo") {
        rx += $2;   # RX bytes
        tx += $10;  # TX bytes
      }
    }
    END {print rx, tx}
  ' /proc/net/dev
}

now_seconds() {
  date +%s.%N
}

# --- Inisialisasi: ambil sample awal ---

read prev_idle prev_total <<< "$(get_cpu_times)"
read prev_read_sectors prev_write_sectors <<< "$(get_disk_sectors)"
read prev_rx_bytes prev_tx_bytes <<< "$(get_net_bytes)"
prev_time=$(now_seconds)

# Tunggu 1 interval sebelum sample pertama (agar punya delta)
sleep "$INTERVAL"

# --- Loop utama ---
while true; do
  curr_time=$(now_seconds)

  # Hitung selang waktu (dt)
  dt=$(awk -v n="$curr_time" -v p="$prev_time" 'BEGIN {printf "%.3f", n - p}')

  # Timestamp untuk log (format ISO-ish)
  ts=$(date +%Y-%m-%dT%H:%M:%S)

  # CPU
  read curr_idle curr_total <<< "$(get_cpu_times)"
  cpu_idle_pct=$(awk -v pidle="$prev_idle" -v ptotal="$prev_total" \
                     -v cidle="$curr_idle" -v ctotal="$curr_total" '
    BEGIN {
      diff_total = ctotal - ptotal;
      diff_idle  = cidle - pidle;
      if (diff_total <= 0) {
        printf "0.00";
      } else {
        printf "%.2f", (diff_idle * 100.0) / diff_total;
      }
    }')

  # RAM available (MB)
  ram_available_mb=$(get_ram_available_mb)

  # Disk sectors
  read curr_read_sectors curr_write_sectors <<< "$(get_disk_sectors)"
  disk_read_kbs=$(awk -v pr="$prev_read_sectors" -v cr="$curr_read_sectors" \
                      -v dt="$dt" -v ss="$SECTOR_SIZE" '
    BEGIN {
      diff = cr - pr;
      if (dt <= 0 || diff < 0) {
        printf "0.00";
      } else {
        printf "%.2f", diff * ss / 1024.0 / dt;
      }
    }')
  disk_write_kbs=$(awk -v pw="$prev_write_sectors" -v cw="$curr_write_sectors" \
                       -v dt="$dt" -v ss="$SECTOR_SIZE" '
    BEGIN {
      diff = cw - pw;
      if (dt <= 0 || diff < 0) {
        printf "0.00";
      } else {
        printf "%.2f", diff * ss / 1024.0 / dt;
      }
    }')

  # Network bytes
  read curr_rx_bytes curr_tx_bytes <<< "$(get_net_bytes)"
  net_rx_kbs=$(awk -v pr="$prev_rx_bytes" -v cr="$curr_rx_bytes" -v dt="$dt" '
    BEGIN {
      diff = cr - pr;
      if (dt <= 0 || diff < 0) {
        printf "0.00";
      } else {
        printf "%.2f", diff / 1024.0 / dt;
      }
    }')
  net_tx_kbs=$(awk -v pt="$prev_tx_bytes" -v ct="$curr_tx_bytes" -v dt="$dt" '
    BEGIN {
      diff = ct - pt;
      if (dt <= 0 || diff < 0) {
        printf "0.00";
      } else {
        printf "%.2f", diff / 1024.0 / dt;
      }
    }')

  # Tulis ke CSV + echo ke terminal
  line="$ts,$cpu_idle_pct,$ram_available_mb,$disk_read_kbs,$disk_write_kbs,$net_rx_kbs,$net_tx_kbs"
  echo "$line" | tee -a "$LOGFILE"

  # Update nilai previous untuk iterasi berikutnya
  prev_idle=$curr_idle
  prev_total=$curr_total
  prev_read_sectors=$curr_read_sectors
  prev_write_sectors=$curr_write_sectors
  prev_rx_bytes=$curr_rx_bytes
  prev_tx_bytes=$curr_tx_bytes
  prev_time=$curr_time

  # Tunggu interval berikutnya
  sleep "$INTERVAL"
done
