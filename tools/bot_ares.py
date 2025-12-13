import requests
import time
import sys

# --- KONFIGURASI ---
# GANTI DENGAN IP DVWA ANDA
TARGET_IP = "192.168.18.21" 
URL = f"http://{TARGET_IP}/dvwa/vulnerabilities/exec/"

# Header Khas Bot Ares (Jangan diubah, ini ciri khas signature-nya)
HEADERS = {
    'User-Agent': 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; Ares)',
    'Connection': 'Keep-Alive',
    'Content-Type': 'application/x-www-form-urlencoded'
}

# Payload yang SELALU SAMA (Agar ukuran paket statis)
FIXED_PAYLOAD = {'id': 'bot_12345', 'status': 'ready_to_attack', 'cmd': 'waiting'}

def simulate_noisy_bot():
    print(f"[*] Memulai Bot Ares Mode 'BERISIK' ke {URL}")
    print("[*] Interval: TEPAT 0.5 detik (Pola Robot)")
    print("[*] Tekan Ctrl+C untuk berhenti...")
    
    count = 0
    try:
        while True:
            # 1. Kirim Request
            # timeout pendek agar jika server sibuk, dia langsung coba lagi (agresif)
            response = requests.post(URL, headers=HEADERS, data=FIXED_PAYLOAD, timeout=2)
            
            count += 1
            print(f"[{count}] Paket Bot Terkirim! (Size Tetap, Pola Tetap)")
            
            # 2. JEDA WAKTU YANG KAKU (KUNCI DETEKSI ML)
            # Jangan pakai random! Pakai angka pasti.
            # 0.5 detik = 2 kali per detik (Cukup cepat tapi bukan DoS)
            time.sleep(0.5) 

    except KeyboardInterrupt:
        print("\n[!] Bot dihentikan.")
    except Exception as e:
        print(f"[!] Error: {e}")

if __name__ == "__main__":
    simulate_noisy_bot()