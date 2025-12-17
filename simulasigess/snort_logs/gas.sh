#!/bin/bash
# ========================================
# SnortML Automation Script (ROOT)
# ========================================

set -e

SNORT_BIN="/usr/local/bin/snort"
SNORT_LUA="/usr/local/etc/snort/snort.lua"

# ==== PATH FIX (PCAP BENAR) ====
PCAP_BASE="/home/snort/snort/pengujian"

MODEL_DIR="/usr/local/etc/snort/models"
LOG_BASE="/var/log/snort"

MODELS=("rf" "mlp" "lgbm" "ae")
ATTACKS=(
  "ftphydra" "ftppatator" "goldeneye" "nmap"
  "slowhttp" "slowloris"
  "sshhydra" "sshpatator"
  "webbrute" "websql" "webxss"
)

THRESHOLD=0.95
BODY_DEPTH=-1

echo "[INFO] Running as user: $(whoami)"
echo "[INFO] PCAP BASE: $PCAP_BASE"
echo "========================================"

# ==== MAIN LOOP ====
for model in "${MODELS[@]}"; do
  for attack in "${ATTACKS[@]}"; do

    MODEL_PATH="${MODEL_DIR}/${model}.tflite"
    PCAP_FILE="${PCAP_BASE}/${attack}/serangan_A_fix.pcap"
    LOG_DIR="${LOG_BASE}"

    echo "[INFO] Model  : $model"
    echo "[INFO] Attack : $attack"
    echo "[INFO] PCAP   : $PCAP_FILE"
    echo "[INFO] Log    : $LOG_DIR"

    # --- VALIDASI FILE ---
    if [[ ! -f "$PCAP_FILE" ]]; then
      echo "[WARN] PCAP NOT FOUND → SKIP"
      echo "----------------------------------------"
      continue
    fi

    if [[ ! -f "$MODEL_PATH" ]]; then
      echo "[WARN] MODEL NOT FOUND → SKIP"
      echo "----------------------------------------"
      continue
    fi

    # --- LOG DIR ---
    mkdir -p "$LOG_DIR"
    chown snort:snort "$LOG_DIR"
    chmod 777 "$LOG_DIR"
    # --- RUN SNORT ---
    $SNORT_BIN \
      -c "$SNORT_LUA" \
      --talos \
      --lua "
        snort_ml_engine = { http_param_model = \"$MODEL_PATH\" };
        snort_ml = {
          client_body_depth = $BODY_DEPTH,
          http_param_threshold = $THRESHOLD
        };
        trace = { modules = { snort_ml = { all = 1 } } };
      " \
      -A alert_fast \
      -l "$LOG_DIR" \
      -s 65535 \
      -k none \
      -Q \
      -r "$PCAP_FILE"

    echo "[DONE] $model - $attack"
    echo "----------------------------------------"
  done
done

echo "[ALL DONE] All simulations finished."
