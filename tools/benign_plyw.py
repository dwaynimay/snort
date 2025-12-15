import time
import random
from playwright.sync_api import sync_playwright

# --- KONFIGURASI ---
# Ganti dengan IP Target DVWA Anda
TARGET_IP = "192.168.1.16"
BASE_URL = f"http://{TARGET_IP}/dvwa/login.php"
USERNAME = "admin"
PASSWORD = "password"

max_actions = 30
# Daftar Menu SESUAI GAMBAR YANG ANDA KIRIM
# (Saya hapus 'Logout' agar bot tidak keluar sendiri)
MENU_ITEMS = [
    "Home",
    "Instructions",
    "Setup / Reset DB",
    "Brute Force",
    "Command Injection",
    "CSRF",
    "File Inclusion",
    "File Upload",
    "Insecure CAPTCHA",
    "SQL Injection",
    "SQL Injection (Blind)",
    "Weak Session IDs",
    "XSS (DOM)",
    "XSS (Reflected)",
    "XSS (Stored)",
    "CSP Bypass",
    "JavaScript Attacks",
    "Authorisation Bypass",
    "Open HTTP Redirect",
    "Cryptography",
    "API",
    "DVWA Security",
    "PHP Info",
    "About"
]


def run_benign_traffic():
    print("[*] Memulai Simulasi User Normal dengan Playwright (Chromium)...")

    with sync_playwright() as p:
        # headless=True artinya browser tidak muncul di layar (background mode)
        # Ubah ke False jika ingin melihat browsernya jalan sendiri
        browser = p.chromium.launch(channel="msedge", headless=False)

        # Setting User Agent layaknya browser Chrome di Windows
        context = browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
            viewport={'width': 1280, 'height': 720}
        )
        page = context.new_page()

        try:
            # --- TAHAP 1: LOGIN ---
            print(f"[*] Membuka halaman login: {BASE_URL}")
            page.goto(BASE_URL)

            if "login.php" in page.url:
                print("[*] Memasukkan credential...")
                page.fill('input[name="username"]', USERNAME)
                page.fill('input[name="password"]', PASSWORD)
                page.click('input[name="Login"]')
                page.wait_for_load_state('networkidle')

            if "Welcome to Damn Vulnerable Web App" in page.content():
                print("[+] Login Berhasil! Memulai browsing acak...")
            else:
                print("[-] Login mungkin gagal, mencoba lanjut browsing...")

            # --- TAHAP 2: BROWSING ACAK (LOOP) ---
            action_count = 0
            while True:
                # Pilih satu menu secara acak dari daftar
                if action_count >= max_actions:
                    print(
                        f"\n[DONE] Mencapai batas {max_actions} aksi. Selesai.")
                    break

                menu_text = random.choice(MENU_ITEMS)

                try:
                    action_count += 1
                    print(
                        f"[{action_count}/{max_actions}] Mengklik menu: {menu_text}")

                    # Playwright mencari tombol berdasarkan teks di sidebar
                    page.click(f"text={menu_text}", timeout=3000)

                    # Tunggu loading selesai
                    page.wait_for_load_state('domcontentloaded')
                    action_count += 1

                    # --- JEDA WAKTU (PENTING UNTUK BENIGN) ---
                    # Manusia membaca halaman sekitar 2 sampai 5 detik sebelum klik lagi
                    sleep_sec = random.uniform(2.0, 5.0)
                    time.sleep(sleep_sec)

                except Exception as e:
                    # Kadang menu CSP Bypass / JavaScript Attacks membuka tab baru atau error
                    print(f"[!] Gagal klik '{menu_text}'. Skip ke menu lain.")
                    # Jika stuck, paksa kembali ke Home
                    page.goto(f"http://{TARGET_IP}/dvwa/index.php")

        except KeyboardInterrupt:
            print("\n[!] Simulasi dihentikan oleh user (Ctrl+C).")
        except Exception as e:
            print(f"\n[ERROR] Terjadi kesalahan sistem: {e}")
        finally:
            print("[*] Menutup Browser.")
            browser.close()


if __name__ == "__main__":
    run_benign_traffic()
