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
SNORT_DIR="/usr/local/etc/snort"
SNORT_LOG_DIR="/var/log/snort"
SNORT_RULES_DIR="$SNORT_DIR/rules"
SNORT_RULES_FILE="$SNORT_RULES_DIR/rules.local"
SNORT_LUA="$SNORT_DIR/snort.lua"
SNORT_ML_DIR="$SNORT_DIR/ml"
WAZUH_CONFIG="/var/ossec/etc/ossec.conf"
PCAPGEN_FILE="sqlpcap.py"
PCAPGEN_CP_DIR="/usr/local/src/libml/examples/classifier"

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
    # deependensi global
    ca-certificates curl wget git nano vim net-tools iproute2 
    iputils-ping rsyslog sudo tzdata ethtool openssh-server
    # dependensi snort
    asciidoc autoconf automake bison build-essential checkinstall 
    cmake cpputest dblatex flex g++ gawk gdb jq libcpputest-dev 
    libdnet-dev libdumbnet-dev libfl-dev libflatbuffers-dev 
    libgoogle-perftools-dev libhwloc-dev libhyperscan-dev 
    libjemalloc-dev libluajit-5.1-dev liblzma-dev libmnl-dev 
    libnetfilter-queue-dev libnghttp2-dev libpcap-dev libpcre2-dev 
    libsafec-dev libsqlite3-dev libssl-dev libtirpc-dev libtool 
    libunwind-dev make netcat-openbsd pkg-config python3 
    python3-pip python3-venv tcpdump uuid-dev w3m zlib1g-dev
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

# # buat user agar tidak root
# user snorty
# if ! id -u snorty >/dev/null 2>&1; then
#   echo "  -> Creating user snorty:oink"
#   useradd -m -s /bin/bash snorty
#   echo "snorty:oink" | chpasswd
#   usermod -aG sudo snorty
# fi

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
install_component "snort3" "https://github.com/snort3/snort3.git" "./configure_cmake.sh --prefix=/usr/local --enable-debug-msgs && cd build && make -j$(nproc) && make install && ldconfig"
# Extra
install_component "snort3_extra" "https://github.com/snort3/snort3_extra.git" "./configure_cmake.sh --prefix=/usr/local && cd build && make -j$(nproc) && make install && ldconfig"

info "Configuring Snort 3..."
mkdir -p "$SNORT_RULES_DIR" "$SNORT_LOG_DIR" "$SNORT_ML_DIR"
chmod 777 "$SNORT_RULES_DIR" "$SNORT_LOG_DIR" "$SNORT_ML_DIR"

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
ExecStart=/usr/local/bin/snort -c $SNORT_LUA -s 65535 -k none -i $ACTIVE_IFACE -A alert_fast -l $SNORT_LOG_DIR -R $SNORT_DIR/rules -Q --daq afpacket
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >>"$LOG_FILE" 2>&1
systemctl enable snort3-nic.service snort.service >>"$LOG_FILE" 2>&1
systemctl start snort3-nic.service snort.service >>"$LOG_FILE" 2>&1
success "Snort 3 installed and services started."

# copy pcapgen
cp "$PCAPGEN_FILE" "$PCAPGEN_CP_DIR"
chmod +x "$PCAPGEN_CP_DIR/$PCAPGEN_FILE"
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
        systemctl restart wazuh-manager
        success "Wazuh linked to Snort logs."
    else
        info "Wazuh config already present."
    fi
else
    error "Wazuh config file not found!"
fi

# --- 5. REPORT ---
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