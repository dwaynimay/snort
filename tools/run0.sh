#!/bin/bash

# Pastikan script dijalankan sebagai root/sudo
if [[ $EUID -ne 0 ]]; then
   echo "Harap jalankan script ini dengan sudo!"
   exit 1
fi

# Menggunakan satu timestamp dasar untuk folder atau penanda
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "--- [1] Mengatur VETH Pair & MTU 9000 ---"
#ip link set enp0s3 mtu 9000

echo "--- [2] Menjalankan TCPDUMP (Background) ---"
# Tcpdump tetap kita simpan ke file pcap untuk analisis Wireshark
tcpdump -i enp0s3 -s 0 -nn "host 192.168.1.21 and host 192.168.1.18" -w "log_packet_$TIMESTAMP.pcap" &
TCPDUMP_PID=$!

echo "--- [3] Menjalankan Script Hardware Log Anda ---"
if [ -f ~/snort/tools/log_hardware.sh ]; then
    # Menjalankan script Anda. Karena script Anda sudah pakai 'tee' dan punya 
    # nama file sendiri, kita jalankan saja di background.
    # > /dev/null agar output terminal script hardware tidak menumpuk dengan Snort.
    bash ~/snort/tools/log_hardware.sh > /dev/null &
    HW_LOG_PID=$!
    echo "Script Hardware aktif. File CSV otomatis dibuat oleh script Anda."
else
    echo "Peringatan: ~/snort/tools/log_hardware.sh TIDAK DITEMUKAN!"
fi

echo "--- [4] Menjalankan Snort 3 ML Engine ---"
echo "Menunggu 3 detik agar semua logger siap..."
sleep 3

# Fungsi Cleanup saat Ctrl+C
cleanup() {
    echo -e "\n--- Menghentikan Pengujian ---"
    kill $TCPDUMP_PID
    [ ! -z "$HW_LOG_PID" ] && kill $HW_LOG_PID
    echo "Selesai. Cek file PCAP dan file CSV Hardware Anda."
    exit
}
trap cleanup SIGINT