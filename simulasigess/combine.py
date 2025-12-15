import os

BASE_DIR = "snort_logs"
SOURCE_FILE = "alert_fast.txt"
OUTPUT_FILE = "alert_fast_all.txt"

def merge_alerts():
    with open(OUTPUT_FILE, "a", encoding="utf-8", errors="ignore") as out:
        for model in os.listdir(BASE_DIR):
            model_path = os.path.join(BASE_DIR, model)
            if not os.path.isdir(model_path):
                continue

            for attack in os.listdir(model_path):
                attack_path = os.path.join(model_path, attack)
                if not os.path.isdir(attack_path):
                    continue

                alert_path = os.path.join(attack_path, SOURCE_FILE)
                if not os.path.isfile(alert_path):
                    continue

                with open(alert_path, "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        out.write(line)

if __name__ == "__main__":
    merge_alerts()
