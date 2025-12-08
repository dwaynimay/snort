#!/bin/bash
set -e


################################################################################
# Konfigurasi dan Variabel
################################################################################

# --- Warna ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;96m'
NC='\033[0m'

# --- Paths ---
LOG_FILE="/var/log/snortEnv.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WAZUH_CONFIG="/var/ossec/etc/ossec.conf"
WAZUH_CONFIG_DECODER="/var/ossec/etc/decoders/local_decoder.xml"
WAZUH_CONFIG_RULES="/var/ossec/etc/rules/local_rules.xml"

# --- System Info ---
ACTIVE_IFACE=$(ip route get 1 | awk '{print $5; exit}') || ACTIVE_IFACE="enp0s3"
VM_IP=$(ip route get 1 | awk '{print $7; exit}') || VM_IP="Unknown"
REAL_USER="${SUDO_USER:-$(whoami)}"


################################################################################
# HELPER FUNCTIONS
################################################################################

banner() {
    clear
    echo -e "${YELLOW}"
    cat << "EOF"
 ██████╗ █████╗ ██████╗ ███████╗████████╗ ██████╗ ███╗   ██╗███████╗
██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔═══██╗████╗  ██║██╔════╝
██║     ███████║██████╔╝███████╗   ██║   ██║   ██║██╔██╗ ██║█████╗  
██║     ██╔══██║██╔═══╝ ╚════██║   ██║   ██║   ██║██║╚██╗██║██╔══╝  
╚██████╗██║  ██║██║     ███████║   ██║   ╚██████╔╝██║ ╚████║███████╗
 ╚═════╝╚═╝  ╚═╝╚═╝     ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚══════╝
                                                                    
███╗   ███╗ █████╗ ███╗   ██╗██╗ █████╗                             
████╗ ████║██╔══██╗████╗  ██║██║██╔══██╗                            
██╔████╔██║███████║██╔██╗ ██║██║███████║    █████╗                  
██║╚██╔╝██║██╔══██║██║╚██╗██║██║██╔══██║    ╚════╝                  
██║ ╚═╝ ██║██║  ██║██║ ╚████║██║██║  ██║                            
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝                            
EOF
    echo -e "${NC}"
    echo -e "${BLUE}[INFO] Log Penyimpanan: ${LOG_FILE}${NC}"
    echo ""
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "run as Root (sudo ./installManager.sh)"
    fi
}

################################################################################
# Instalasi
################################################################################

banner
check_root

echo "=== Setting non-interactive mode ==="
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

# Update & Dependensi
info "[1/2] Updating system and installing base packages..."
apt-get update >>"$LOG_FILE" 2>&1
apt-get upgrade -y >>"$LOG_FILE" 2>&1

PACKAGES=(
    ca-certificates curl nano iproute2 iputils-ping rsyslog sudo tzdata openssh-server tcpdump htop dstat
)

apt-get install --no-install-recommends -y "${PACKAGES[@]}" >>"$LOG_FILE" 2>&1

ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
timedatectl set-timezone Asia/Jakarta
timedatectl set-ntp true
systemctl restart systemd-timesyncd 2>/dev/null || true

# Konfigurasi SSH
systemctl enable ssh >/dev/null 2>&1 || true
systemctl start ssh  >/dev/null 2>&1 || true
SSH_STATUS=$(systemctl is-active ssh || echo "unknown")

success "System updated & dependencies installed."

# Instal Wazuh
info "[2/2] Installing Wazuh All in One"
cd /tmp
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh >>"$LOG_FILE" 2>&1
bash wazuh-install.sh -a | tee -a "$LOG_FILE"

if [ -f "$WAZUH_CONFIG_RULES" ]; then
    cp "$WAZUH_CONFIG_RULES" "${WAZUH_CONFIG_RULES}.bak"
    sed -i '$a \
    \
    <group name="snort_ml">\
      <rule id="100100" level="10">\
        <match>snort_ml</match>\
        <description>Snort ML Detection: terdeteksi serangan oleh ML Neural Network</description>\
        <group>snort_ml</group>\
      </rule>\
    </group>' "$WAZUH_CONFIG_RULES"
else
    error "Wazuh rules file not found!"
fi

systemctl restart wazuh-manager
WAZUH_STATUS=$(systemctl is-active wazuh-manager || echo "unknown")

################################################################################
# Report
################################################################################

# REPORT
echo -e "${YELLOW}========================================${NC}"
echo -e "${GREEN}      CAPSTONE INSTALLATION REPORT      ${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "${BLUE}SYSTEM INFO:${NC}"
echo "  SSH Status  : $SSH_STATUS"
echo "  Interface   : $ACTIVE_IFACE"
echo "  VM IP       : $VM_IP"
echo "  User        : $REAL_USER"
echo "  Login       : ssh $REAL_USER@$VM_IP"
echo ""
echo -e "${BLUE}SERVICE STATUS:${NC}"
echo "  Manager     : $WAZUH_STATUS"
echo ""
echo -e "${YELLOW}Full Logs: $LOG_FILE${NC}"
echo -e "${YELLOW}========================================${NC}"
