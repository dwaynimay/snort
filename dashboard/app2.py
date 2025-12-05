import subprocess
import os
import signal
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)

DAFTAR_MODEL = {
    "cicids": {
        "nama": "CICIDS MLP (Standard)",
        "file": "/usr/local/src/libml/examples/classifier/models/model_v2.2/cicids_mlp_float32.tflite",
        "threshold": 0.95
    },
    "sensitif": {
        "nama": "Model Eksperimental (Sensitif)",
        "file": "/usr/local/src/libml/examples/classifier/models/model_v2.2/model_lain.tflite",
        "threshold": 0.80
    }
}

proses_snort = None

@app.route('/')
def index():
    return render_template('index.html', models=DAFTAR_MODEL)

@app.route('/start_snort', methods=['POST'])
def start_snort():
    global proses_snort

    data = request.json
    model_id = data.get('model_id')

    if model_id in DAFTAR_MODEL:
        # PERBAIKAN: Gunakan nama variabel yang konsisten
        model = DAFTAR_MODEL[model_id] 

        # PERBAIKAN: Format String Lua
        # Python f-string butuh dobel kurung kurawal {{ }} untuk menghasilkan satu { di output
        lua_config = (
            f"snort_ml_engine = {{ http_param_model = '{model['file']}' }}; "
            f"snort_ml = {{ http_param_threshold = {model['threshold']} }}; "
            "alert_fast = { file = true, limit = 100 }; "
            "trace = { modules = { snort_ml = { all = 1 } } };"
        )

        # Perintah Snort
        # Catatan: Pastikan user yang menjalankan script ini punya akses sudo tanpa password
        # atau jalankan script python ini sebagai root.
        command = (
            f"sudo snort -c /usr/local/etc/snort/snort.lua --talos "
            f"--lua \"{lua_config}\" "
            f"-s 65535 -k none -i enp0s3 -Q --daq afpacket "
            f"-A alert_fast -l /var/log/snort"
        )

        try:
            # Jalankan di background
            proses_snort = subprocess.Popen(command, shell=True)
            return jsonify({"status": "berjalan", "pesan": f"Snort berjalan dengan model: {model['nama']}"})
        except Exception as e:
            return jsonify({"status": "error", "pesan": str(e)})

    return jsonify({"status": "error", "pesan": "Model tidak valid"})

@app.route('/cek_progress', methods=['GET'])
def cek_progress():
    global proses_snort

    # 1. HITUNG TOTAL ALERT
    cmd_hitung = f"sudo cat /var/log/snort/alert_fast.txt* 2>/dev/null | wc -l"
    
    try:
        total = subprocess.check_output(cmd_hitung, shell=True, text=True).strip()
        jumlah_alert = int(total) if total else 0
    except:
        jumlah_alert = 0

    # 2. AMBIL LOG TERAKHIR
    cmd_log = f"sudo cat /var/log/snort/alert_fast.txt* 2>/dev/null | tail -n 5"
    try:
        log_terakhir = subprocess.check_output(cmd_log, shell=True, text=True)
    except:
        log_terakhir = "Menunggu data..."

    # 3. STATUS PROCESS
    # Kita cek apakah ada proses snort yang berjalan di sistem
    try:
        # pgrep akan return exit code 0 jika ada proses snort
        subprocess.check_call("pgrep snort", shell=True, stdout=subprocess.DEVNULL)
        masih_jalan = True
    except subprocess.CalledProcessError:
        masih_jalan = False

    return jsonify({
        "running": masih_jalan,
        "total_alerts": jumlah_alert,
        "latest_log": log_terakhir
    })

if __name__ == '__main__':
    # Disarankan menjalankan: sudo python3 app.py
    app.run(host='0.0.0.0', port=5000, debug=True)