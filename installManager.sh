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

# Preparasi
banner
check_root

echo "=== Setting non-interactive mode ==="
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

# Update & Dependensi
info "[1/5] Updating system and installing base packages..."
apt-get update >>"$LOG_FILE" 2>&1
apt-get upgrade -y >>"$LOG_FILE" 2>&1

PACKAGES=(
    ca-certificates curl git nano iproute2 iputils-ping rsyslog sudo tzdata openssh-server tcpdump htop dstat
)
apt-get install --no-install-recommends -y "${PACKAGES[@]}" >>"$LOG_FILE" 2>&1

# Konfigurasi SSH
systemctl enable ssh >/dev/null 2>&1 || true
systemctl start ssh  >/dev/null 2>&1 || true
SSH_STATUS=$(systemctl is-active ssh || echo "unknown")
success "System updated & dependencies installed."

# Instal Wazuh
info "Installing Wazuh (All-in-One)..."
cd /tmp
curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh >>"$LOG_FILE" 2>&1
bash wazuh-install.sh -a | tee -a "$LOG_FILE"

if [ -f "$WAZUH_CONFIG_DECODER" ]; then
    cp "$WAZUH_CONFIG_DECODER" "${WAZUH_CONFIG_DECODER}.bak"
    sed -i '$a \
    \
    <decoder name="snort_ml_decoder">\
        <prematch>snort_ml</prematch>\
        <regex>^(\d{4}) Snort alert: (\w+) - (.*)$</regex>\
        <order>year,program,alert_message</order>\
    </decoder>' "$WAZUH_CONFIG_DECODER"
else
    error "Wazuh encoder file not found!"
fi

if [ -f "$WAZUH_CONFIG_RULES" ]; then
    cp "$WAZUH_CONFIG_RULES" "${WAZUH_CONFIG_RULES}.bak"
    sed -i '$a \
    \
    <group name="snort_ml,ids,">\
    <rule id="100100" level="7">\
        <decoded_as>snort_ml_decoder</decoded_as>\
        <match>snort_ml</match>\
        <description>SnortML Detection: Potential threat detected</description>\
        <group>ml_alert,ids,</group>\
    </rule>\
    \
    <rule id="100101" level="10">\
        <if_sid>100100</if_sid>\
        <match>Neural Network Based Exploit Detection</match>\
        <description>SnortML Detection: ML Exploit Detection</description>\
        <group>ml_high_confidence,</group>\
    </rule>\
    </group>' "$WAZUH_CONFIG_RULES"
else
    error "Wazuh rules file not found!"
fi

systemctl restart wazuh-manager

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
echo "  Manager     : $(systemctl is-active wazuh-manager)"
echo ""
echo -e "${YELLOW}Full Logs: $LOG_FILE${NC}"
echo -e "${YELLOW}========================================${NC}"