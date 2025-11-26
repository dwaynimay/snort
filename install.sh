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
SNORT_DIR="/usr/local/etc/snort"
SNORT_LOG_DIR="/var/log/snort"
SNORT_RULES_DIR="$SNORT_DIR/rules"
SNORT_RULES_FILE="$SNORT_RULES_DIR/rules.local"
SNORT_LUA="$SNORT_DIR/snort.lua"
SNORT_ML_DIR="$SNORT_DIR/models"
SRC_PCAPGEN="$SCRIPT_DIR/tools/pcap_gen/sqlpcap.py"
SRC_DASHBOARD_APP="$SCRIPT_DIR/dashboard/app.py"
SRC_DASHBOARD_HTML="$SCRIPT_DIR/dashboard/templates/index.html"
DEST_PCAPGEN_DIR="/usr/local/src/libml/examples/classifier"
DEST_DASHBOARD_DIR="/usr/local/src/snort_dashboard"
DEST_TEMPLATE_DIR="$DEST_DASHBOARD_DIR/templates"
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
        error "run as Root (sudo ./install.sh)"
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
    # dependensi global
    ca-certificates curl wget git nano vim net-tools iproute2 gdb jq
    iputils-ping rsyslog sudo tzdata ethtool openssh-server tcpdump netcat-openbsd
    python3 python3-pip python3-venv tcpreplay python3-scapy

    # dependensi dashboard custom
    python3-flask

    # === 3. DEPENDENSI SNORT 3 ===
    # a. Build Tools & Compiler
    build-essential g++ make cmake automake autoconf libtool pkg-config 
    flex bison gawk libfl-dev

    # b. Core Libraries & Protocols
    libpcap-dev libpcre2-dev libdnet-dev libdumbnet-dev libluajit-5.1-dev 
    libssl-dev zlib1g-dev uuid-dev libnghttp2-dev libsqlite3-dev 
    libtirpc-dev libunwind-dev

    # c. Performance & Advanced Libraries
    libhyperscan-dev libhwloc-dev libgoogle-perftools-dev libjemalloc-dev
    liblzma-dev libflatbuffers-dev libmnl-dev libnetfilter-queue-dev

    # d. Documentation & Testing
    asciidoc checkinstall cpputest libcpputest-dev dblatex libsafec-dev w3m
)
apt-get install --no-install-recommends -y "${PACKAGES[@]}" >>"$LOG_FILE" 2>&1

# Konfigurasi SSH
systemctl enable ssh >/dev/null 2>&1 || true
systemctl start ssh  >/dev/null 2>&1 || true
SSH_STATUS=$(systemctl is-active ssh || echo "unknown")
success "System updated & dependencies installed."

# Instal DVWA
info "[2/5] Installing DVWA Stack (Apache + MariaDB + PHP)..."
apt-get install -y apache2 mariadb-server mariadb-client php php-cli php-mysql \
    php-gd php-xml php-curl php-zip libapache2-mod-php git >>"$LOG_FILE" 2>&1

systemctl enable apache2 mariadb >>"$LOG_FILE" 2>&1 || true
systemctl start apache2 mariadb  >>"$LOG_FILE" 2>&1 || true
a2enmod php* rewrite >>"$LOG_FILE" 2>&1 || true
systemctl restart apache2 >>"$LOG_FILE" 2>&1

if [ ! -d /var/www/html/dvwa ]; then
    git clone --depth=1 https://github.com/digininja/DVWA.git /var/www/html/dvwa >>"$LOG_FILE" 2>&1
fi

cd /var/www/html/dvwa
[ ! -f config/config.inc.php ] && cp config/config.inc.php.dist config/config.inc.php

mysql -u root >>"$LOG_FILE" 2>&1 <<EOF
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY 'p@ssw0rd';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';
FLUSH PRIVILEGES;
EOF

chown -R www-data:www-data /var/www/html/dvwa
chmod -R 755 /var/www/html/dvwa
chmod 777 /var/www/html/dvwa/hackable/uploads || true

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")
PHPINI="/etc/php/$PHP_VERSION/apache2/php.ini"
[ -f "$PHPINI" ] && sed -i 's/^\s*allow_url_include\s*=.*/allow_url_include = On/' "$PHPINI" || true
[ -f "$PHPINI" ] && sed -i 's/^\s*allow_url_fopen\s*=.*/allow_url_fopen = On/' "$PHPINI" || true
[ -f "$PHPINI" ] && sed -i 's/^\s*display_errors\s*=.*/display_errors = On/' "$PHPINI" || true
[ -f "$PHPINI" ] && sed -i 's/^\s*display_startup_errors\s*=.*/display_startup_errors = On/' "$PHPINI" || true

systemctl restart apache2 >>"$LOG_FILE" 2>&1
success "DVWA installed and configured."

# Install Snort3
info "[3/5] Installing Snort 3 and Libraries..."

install_component() {
    local name=$1
    local repo=$2
    local build_cmd=$3
    echo "   -> Building $name..."
    rm -rf "/tmp/$name"
    git clone "$repo" "/tmp/$name" >>"$LOG_FILE" 2>&1
    cd "/tmp/$name"
    eval "$build_cmd" >>"$LOG_FILE" 2>&1
}

# LibDAQ
install_component "libdaq" "https://github.com/snort3/libdaq.git" "./bootstrap && ./configure --prefix=/usr/local && make -j$(nproc) && make install && ldconfig"
# LibML
install_component "libml" "https://github.com/snort3/libml.git" "./configure.sh --prefix=/usr/local && cd build && make -j$(nproc) && make install && ldconfig"
# Copy ML Examples
mkdir -p /usr/local/src/libml
cp -r /tmp/libml/examples /usr/local/src/libml/ >>"$LOG_FILE" 2>&1
# Snort3
install_component "snort3" "https://github.com/snort3/snort3.git" "./configure_cmake.sh --prefix=/usr/local --enable-debug-msgs --enable-tcmalloc --enable-jemalloc && cd build && make -j$(nproc) && make install && ldconfig"
# Extra
install_component "snort3_extra" "https://github.com/snort3/snort3_extra.git" "./configure_cmake.sh --prefix=/usr/local && cd build && make -j$(nproc) && make install && ldconfig"

info "Configuring Snort 3..."
mkdir -p "$SNORT_RULES_DIR" "$SNORT_LOG_DIR" "$SNORT_ML_DIR" "$DEST_PCAPGEN_DIR" "$DEST_TEMPLATE_DIR"
chmod 777 "$SNORT_RULES_DIR" "$SNORT_LOG_DIR" "$SNORT_ML_DIR" "$DEST_PCAPGEN_DIR" "$DEST_TEMPLATE_DIR"

[ ! -f "$SNORT_RULES_FILE" ] && touch "$SNORT_RULES_FILE" && chmod 666 "$SNORT_RULES_FILE"
[ ! -f "$SNORT_LOG_DIR/alert_fast.txt" ] && touch "$SNORT_LOG_DIR/alert_fast.txt" && chmod 666 "$SNORT_LOG_DIR/alert_fast.txt"

# Backup & Edit Lua
cp "$SNORT_LUA" "${SNORT_LUA}.bak"
sed -i 's/--\s*enable_builtin_rules/enable_builtin_rules/' "$SNORT_LUA"
sed -i "/enable_builtin_rules = true,/a \\
    mode = 'inline',\\
    rules = [[ \\
        include $SNORT_RULES_FILE \\
    ]]," "$SNORT_LUA"

sed -i 's/--alert_fast = { }/alert_fast = { file = true, limit = 100 },/' "$SNORT_LUA"

# copy pcapgen
# --- 3. Copy & Config PCAP Generator ---
if [ -f "$SRC_PCAPGEN" ]; then
    info " -> Copying Attack Tool (sqlpcap.py)..."
    cp "$SRC_PCAPGEN" "$DEST_PCAPGEN_DIR/sqlpcap.py"
    chmod +x "$DEST_PCAPGEN_DIR/sqlpcap.py"
else
    echo -e "${RED}[WARN] File $SRC_PCAPGEN tidak ditemukan. Skip copy.${NC}"
fi

# --- 4. Copy Dashboard Files ---
if [ -f "$SRC_DASHBOARD_APP" ] && [ -f "$SRC_DASHBOARD_HTML" ]; then
    info " -> Copying Dashboard App & Templates..."
    cp "$SRC_DASHBOARD_APP" "$DEST_DASHBOARD_DIR/app.py"
    cp "$SRC_DASHBOARD_HTML" "$DEST_TEMPLATE_DIR/index.html"
else
    echo -e "${RED}[WARN] File Dashboard (app.py/index.html) tidak lengkap di folder source.${NC}"
fi

# Services
info "Creating Systemd Services..."
# NIC Service
cat > /etc/systemd/system/snort3-nic.service <<EOF
[Unit]
Description=Configure Snort3 NIC (Promisc & Offloads)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link set dev $ACTIVE_IFACE promisc on
ExecStart=/usr/sbin/ethtool -K $ACTIVE_IFACE gro off lro off
TimeoutStartSec=0
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
# Snort Service
cat >/etc/systemd/system/snort.service <<EOF
[Unit]
Description=Snort 3 IPS (Inline)
After=network.target snort3-nic.service

[Service]
Type=simple
ExecStart=/usr/local/bin/snort -c $SNORT_LUA -s 65535 -k none -i $ACTIVE_IFACE -A alert_fast -l $SNORT_LOG_DIR -R $SNORT_RULES_DIR -Q --daq afpacket
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
# custom dashboard
cat > /etc/systemd/system/snort-dashboard.service <<EOF
[Unit]
Description=Snort ML Web Dashboard
After=network.target

[Service]
User=root
WorkingDirectory=$DEST_DASHBOARD_DIR
ExecStart=/usr/bin/python3 app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >>"$LOG_FILE" 2>&1
systemctl enable snort3-nic.service snort.service snort-dashboard.service >>"$LOG_FILE" 2>&1
systemctl start snort3-nic.service snort.service snort-dashboard.service >>"$LOG_FILE" 2>&1
success "Snort 3 installed and services started."

# Instal Wazuh
info "[4/5] Installing Wazuh (All-in-One)..."
cd /tmp
curl -sO https://packages.wazuh.com/4.8/wazuh-install.sh >>"$LOG_FILE" 2>&1
bash wazuh-install.sh -a | tee -a "$LOG_FILE"

info "Configuring Wazuh Manager for Snort..."
if [ -f "$WAZUH_CONFIG" ]; then
    cp "$WAZUH_CONFIG" "${WAZUH_CONFIG}.bak"
    if ! grep -q "alert_fast.txt" "$WAZUH_CONFIG"; then
        sed -i '/<\/ossec_config>/i \
  <localfile>\
    <log_format>snort-fast</log_format>\
    <location>'"$SNORT_LOG_DIR/alert_fast.txt"'</location>\
  </localfile>' "$WAZUH_CONFIG"
    else
        info "Wazuh config already present."
    fi
else
    error "Wazuh config file not found!"
fi
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
success "Wazuh linked to Snort logs."

# REPORT
echo -e "${YELLOW}========================================${NC}"
echo -e "${GREEN}      CAPSTONE INSTALLATION REPORT      ${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "${BLUE}SYSTEM INFO:${NC}"
echo "  SSH Status  : $SSH_STATUS"
echo "  Interface   : $ACTIVE_IFACE"
echo "  VM IP       : $VM_IP"
echo "  User        : $REAL_USER"
echo "  Login       : ssh $USERNAME_USER@$VM_IP"
echo ""
echo -e "${BLUE}COMPONENTS:${NC}"
echo "  DVWA URL    : http://$VM_IP/dvwa (admin / password)"
echo "  Wazuh UI    : https://$VM_IP (See install output for pass)"
echo "  Snort Rules : $SNORT_RULES_FILE"
echo "  ML Model    : $SNORT_ML_DIR"
echo "  Snort Log   : $SNORT_LOG_DIR/alert_fast.txt"
echo ""
echo -e "${BLUE}SERVICE STATUS:${NC}"
echo "  Snort       : $(systemctl is-active snort)"
echo "  Manager     : $(systemctl is-active wazuh-manager)"
echo "  Web (DVWA)  : $(systemctl is-active apache2)"
echo ""
echo -e "${YELLOW}Full Logs: $LOG_FILE${NC}"
echo -e "${YELLOW}========================================${NC}"