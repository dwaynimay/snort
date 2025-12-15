import os
import time

BASE_DIR = "snort_logs"   # folder utama
TARGET_FILE = "alert_fast.txt"
SLEEP_SEC = 3             # interval pantau (detik)

def process_alert(file_path, model, attack):
    """
    Ganti (snort_ml) -> (model_attack)
    """
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    changed = False
    new_lines = []

    tag_old = "(snort_ml)"
    tag_new = f"({model}_{attack})"

    for line in lines:
        if tag_old in line:
            line = line.replace(tag_old, tag_new)
            changed = True
        new_lines.append(line)

    if changed:
        with open(file_path, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
        print(f"[UPDATED] {file_path} -> {tag_new}")

def scan_once():
    for model in os.listdir(BASE_DIR):
        model_path = os.path.join(BASE_DIR, model)
        if not os.path.isdir(model_path):
            continue

        for attack in os.listdir(model_path):
            attack_path = os.path.join(model_path, attack)
            if not os.path.isdir(attack_path):
                continue

            alert_path = os.path.join(attack_path, TARGET_FILE)
            if os.path.isfile(alert_path):
                process_alert(alert_path, model, attack)

if __name__ == "__main__":
    print("[INFO] Monitoring snort alert folders...")
    while True:
        scan_once()
        time.sleep(SLEEP_SEC)
