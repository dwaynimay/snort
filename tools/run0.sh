#!/bin/bash

# Pastikan script dijalankan sebagai root/sudo
if [[ $EUID -ne 0 ]]; then
   echo "Harap jalankan script ini dengan sudo!"
   exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "--- [1] Mengatur Interface enp0s3 ---"
ip link set enp0s3 promisc on

echo "--- [2] Menjalankan TCPDUMP (Background) ---"
# Tcpdump tetap di background agar kita bisa lanjut ke script hardware
# Menangkap trafik antara attacker (.18) dan target (.21)
tcpdump -i enp0s3 -s 0 -nn "host 192.168.1.21 and host 192.168.1.18" -w "log_packet_$TIMESTAMP.pcap" &
TCPDUMP_PID=$!
echo "Tcpdump aktif menangkap paket (PID: $TCPDUMP_PID)..."

# Fungsi Cleanup saat Ctrl+C
# Ini akan mematikan tcpdump saat Anda menghentikan script hardware
cleanup() {
    echo -e "\n--- Menghentikan Pengambilan Data ---"
    
    # Matikan tcpdump
    if [ ! -z "$TCPDUMP_PID" ]; then
        kill $TCPDUMP_PID
    fi
    
    # Paksa tulis data ke disk agar file tidak korup/kosong
    sync
    
    echo "Selesai. Data tersimpan di:"
    echo "- log_packet_$TIMESTAMP.pcap"
    echo "- hardware_log_*.csv (Cek di folder saat ini)"
    exit
}

# Pasang Trap agar jika kita Ctrl+C, tcpdump ikut mati
trap cleanup SIGINT

echo "--- [3] Menjalankan Log Hardware (Foreground) ---"
echo "Menunggu 2 detik agar tcpdump siap..."
sleep 2

if [ -f log_hardware.sh ]; then
    echo "Memulai logging hardware... Tekan Ctrl+C untuk berhenti."
    # JALANKAN DI FOREGROUND (Tanpa tanda &)
    # Output akan muncul langsung di terminal Anda karena script hardware Anda pakai 'tee'
    bash log_hardware.sh
else
    echo "Error: ~/snort/tools/log_hardware.sh tidak ditemukan!"
    kill $TCPDUMP_PID
    exit 1
fi