#!/bin/bash
# =====================================================
# FULL NFQUEUE + VETH + BRIDGE + SNORT SETUP
# Safe to run after VM restore point
# =====================================================

set -e

### CONFIG ###
VETH0="veth0"
VETH1="veth1"
BRIDGE="br0"
QUEUE_NUM=0

SNORT_BIN="/usr/local/bin/snort"
SNORT_CONF="/usr/local/etc/snort/snort.lua"
MODEL_PATH="/usr/local/etc/snort/models/ae.tflite"

echo "[*] Cleaning old interfaces if exist..."
ip link del $VETH0 2>/dev/null || true
ip link del $BRIDGE 2>/dev/null || true

echo "[*] Creating veth pair..."
ip link add $VETH0 type veth peer name $VETH1
ip link set $VETH0 up
ip link set $VETH1 up

echo "[*] Creating bridge..."
ip link add name $BRIDGE type bridge
ip link set $BRIDGE up
ip link set $VETH0 master $BRIDGE
ip link set $VETH1 master $BRIDGE

sudo ip link set veth0 mtu 9000
sudo ip link set veth1 mtu 9000
sudo ip link set br0 mtu 9000

echo "[*] Loading br_netfilter kernel module..."
modprobe br_netfilter || {
  echo "[!] Failed to load br_netfilter module"
  exit 1
}

echo "[*] Enabling bridge netfilter (CRITICAL)..."
sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null
sysctl -w net.bridge.bridge-nf-call-ip6tables=1 >/dev/null


echo "[*] Cleaning old iptables NFQUEUE rules..."
iptables -D FORWARD -j NFQUEUE --queue-num $QUEUE_NUM 2>/dev/null || true

echo "[*] Adding iptables NFQUEUE rule..."
iptables -I FORWARD -j NFQUEUE --queue-num $QUEUE_NUM

echo "[*] Verifying iptables rule..."
iptables -nvL FORWARD | grep NFQUEUE || {
  echo "[!] NFQUEUE rule not found!"
  exit 1
}

echo "[*] Starting Snort (NFQUEUE inline)..."
echo "======================================"

exec sudo $SNORT_BIN \
  -c $SNORT_CONF \
  --talos \
  -Q \
  --daq nfq \
  --daq-var queue=$QUEUE_NUM \
  --lua "snort_ml_engine = { http_param_model = \"$MODEL_PATH\" };" \
  --lua "snort_ml = { http_param_threshold = 0.5 };" \
  --lua "trace = { modules = { snort_ml = { all = 1 } } };" \
  --lua "alert_fast = { file = false }" \
  -A alert_fast \
  -s 65535 \
  -k none
