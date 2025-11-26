import subprocess
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)

# konfigurasi path
SNORT_BIN = "/usr/local/bin/snort"
SNORT_CONF = "/usr/local/etc/snort/snort.lua"
PCAP_FILE = "/usr/local/src/libml/examples/classifier/sql_injection.pcap"
MODEL_DIR = "/usr/local/src/libml/examples/classifier/models/model_v2.2"

# pengaturan model
AVAILABLE_MODELS = {
    "cicids_mlp": {
        "file": f"{MODEL_DIR}/cicids_mlp_float32.tflite",
        "threshold": 0.95
    },

    "model_sensitif": {
        "file": f"{MODEL_DIR}/model_lain.tflite",
        "threshold": 0.80
    }
}

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/run_snort', methods=['POST'])
def run_snort():
    data = request.json
    model_key = data.get('model_id')

    if model_key not in AVAILABLE_MODELS:
        return jsonify({"status": "error", "output": "Model ID tidak valid!"})

    selected_config = AVAILABLE_MODELS[model_key]
    model_path = selected_config["file"]
    model_threshold = selected_config["threshold"]

    # konfigurasi snort lua
    lua_config = (
        f"snort_ml_engine = {{ http_param_model = '{model_path}' }}; "
        f"snort_ml = {{ http_param_threshold = {model_threshold} }}; "
        "trace = { modules = { snort_ml = { all = 1 } } };"
    )

    command = [
        "sudo", SNORT_BIN,
        "-c", SNORT_CONF,
        "--talos",
        "-q",
        "--lua", lua_config,
        "-r", PCAP_FILE,
        "-A", "alert_fast"
    ]

    try:
        # pake perintah subprosess agar bisa kirim ke cli -> python punya akses ke sistem operasi
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        output_log = result.stdout + "\n" + result.stderr

        if result.returncode == 0:
            return jsonify({"status": "success", "output": output_log})
        else:
            return jsonify({"status": "error", "output": output_log})

    except subprocess.TimeoutExpired:
        return jsonify({"status": "error", "output": "Timeout: Snort process took too long."})
    except Exception as e:
        return jsonify({"status": "error", "output": str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)