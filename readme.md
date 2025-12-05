# Snort3 + LibML + Wazuh Integration

![Snort3](https://img.shields.io/badge/Snort-3-blue?style=flat-square&logo=snort)
![Wazuh](https://img.shields.io/badge/Wazuh-SIEM-orange?style=flat-square&logo=wazuh)
![Ubuntu](https://img.shields.io/badge/OS-Ubuntu%2022.04-E95420?style=flat-square&logo=ubuntu)

> **Project Capstone / Eksperimen Keamanan Jaringan** > Implementasi Next-Generation IDS menggunakan Snort3 dengan integrasi LibML (Machine Learning) dan monitoring terpusat via Wazuh SIEM.

---

## Daftar Isi

- [Tentang Project](#-tentang-project)
- [Arsitektur SnortML](#-arsitektur-snortml)
- [Syarat Model Machine Learning](#-syarat-model-machine-learning)
- [Lab Environment](#-lab-environment)
- [Instalasi & Penggunaan](#-instalasi--penggunaan)
- [Referensi](#-referensi)

---

## Tentang Project

Project ini bertujuan untuk mengeksplorasi konfigurasi **Snort3** dengan integrasi **LibML**. LibML (atau dikenal sebagai SnortML) merupakan _detection engine_ berbasis Machine Learning yang menggunakan model _Neural Network_ untuk mendeteksi anomali trafik.

Pendekatan ini bertujuan untuk melengkapi atau bahkan menggantikan metode deteksi tradisional berbasis _signature_ (rules) yang kaku, sehingga sistem dapat mendeteksi serangan yang belum diketahui polanya (_zero-day_) atau variasi serangan yang dimodifikasi.

Semua alert yang dihasilkan oleh Snort akan dikirimkan dan divisualisasikan secara _real-time_ menggunakan **Wazuh SIEM**.

---

## Arsitektur SnortML

SnortML bekerja dengan dua komponen utama di dalam pipeline inspeksi Snort3:

1.  **`snort_ml_inspector`** (Feature Extractor)  
    Bertugas mengambil data mentah dari paket jaringan dan mengubahnya menjadi fitur statistik (vector) yang dapat dipahami oleh model.
2.  **`snort_ml_engine`** (Inference Engine)  
    Bertugas memproses data dari inspector menggunakan model yang sudah dilatih untuk mengambil keputusan (Attack / Normal).

> **Catatan (Nov 2025):** > Saat ini modul `snort_ml_engine` baru mendukung 1 tipe model, yaitu **`http_param_model`**.

---

## Syarat Model Machine Learning

Agar model Machine Learning buatan sendiri dapat berjalan di dalam ekosistem Snort (SnortML), model tersebut harus memenuhi spesifikasi ketat berikut:

- **Framework:** Wajib dibangun menggunakan **TensorFlow**.
- **Arsitektur:** Harus memiliki **1 Input Tensor** dan **1 Output Tensor**.
- **Klasifikasi:** Hanya mendukung **Binary Classifier** (Output berupa probabilitas tunggal: Serangan [1] atau Normal [0]).
- **Tipe Data:** Wajib menggunakan **32-bit Floating Point (`float32`)** untuk input dan output tensor.
- **Format File:** Output model yang diekspor dapat berupa format **`.tflite`** (TensorFlow Lite).

---

## Lab Environment

Spesifikasi lingkungan uji coba yang digunakan dalam eksperimen ini:

Cek memory

```bash
free -h
```

Cek storage

```bash
df -h
```

```bash
~/snort$ free -h
               total        used        free      shared  buff/cache   available
Mem:            10Gi       6.4Gi       154Mi       4.0Mi       3.6Gi       3.4Gi
Swap:             0B          0B          0B
~/snort$ df -h
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           1.1G  1.2M  1.1G   1% /run
/dev/sda2        62G   18G   42G  30% /
tmpfs           5.1G  512K  5.1G   1% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           1.1G  4.0K  1.1G   1% /run/user/1000

```

**Download Source:**

- **Ubuntu Server 22.04.5 LTS:** [Official Download Link](https://ubuntu.com/download/server/thank-you?version=22.04.5&architecture=amd64&lts=true)
- **Ukuran ISO:** 1.98 GB (2,136,926,208 bytes)

---

## Instalasi & Penggunaan

Repositori ini menyertakan script instalasi otomatis (`install.sh`) yang mencakup:

1.  Instalasi Dependensi & Network Config (Promisc Mode & Offload Disable).
2.  Instalasi **DVWA** (Target Serangan).
3.  Build & Install **Snort3 + LibML**.
4.  Instalasi **Wazuh Manager** (All-in-One).
5.  Konfigurasi integrasi Log (`alert_fast.txt`).

### Setup

konfigurasi vm

```bash
VM settings -> Network -> Attached to (Bridged Adapter) -> Name (sesuaikan dengan yang digunakan) -> promiscuous Mode (Allow All)
```

clone repositori

```bash
git clone https://github.com/dwaynimay/snort.git
```

```bash
cd ~/snort
```

beri izin eksekusi

```bash
chmod +x install.sh
```

jalankan sebagai root

```bash
sudo ./install.sh
```

### Cara menggunakan SSH

cek ip address

```bash
ip a
```

atau
panggil interface: ganti enp0s3 dengan interface yang digunakan

```bash
ip a show enp0s3
```

jalankan ssh

```bash
ssh user@ip_address
```

jika figerprint bermasalah

```bash
ssh-keygen -R ip_address
```

### Menggunakan Snort

versi snort

```bash
snort -V
```

snort help

```bash
snort -?
```

```bash
snort --help
```

### Generate simulasi SQL Injection pcap

```bash
cd /usr/local/src/libml/examples/classifier
```

buat virtual environment

```bash
python3 -m venv venv
```

aktifkan virtual environment

```bash
source venv/bin/activate
```

instal scapy untuk jalankan pcap generator

```bash
pip install scapy
```

jalankan pcap generator

```bash
python3 sqlpcap.py
```

melihat isi pcap

```bash
tcpdump -r sql_injection.pcap
```

### Train Model

```bash
pip install numpy tensorflow
```

```bash
./train.py
```

### Jalankan Snort dengan Model

```bash
snort -c /usr/local/etc/snort/snort.lua --talos --lua 'snort_ml_engine = { http_param_model = "classifier.model" }; snort_ml = {}; trace = { modules = { snort_ml = {all =1 } } };' -r sql_injection.pcap
```

## Referensi

- [Dokumentasi Resmi SnortML](https://docs.snort.org/misc/snort_ml)
- [Snort3 GitHub Repository](https://github.com/snort3/snort3)
- [Wazuh Documentation](https://documentation.wazuh.com/)



hardware
apt-get update
apt-get install -y dstat
dstat -tcmdn --output /path/ke/nama_file.csv 1
