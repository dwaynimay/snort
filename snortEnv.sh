#!/bin/sh
set -e

LOG_FILE="/var/log/snortEnv.log"

echo "=== SNORT ENV INSTALLER ==="
echo

##############################
# CEK WAJIB ROOT
##############################
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root (sudo ./snortEnv.sh)"
  exit 1
fi

echo "=== Setting non-interactive mode ==="
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC

##############################
# UPDATE DAN INSTALL DEPENDENSI GLOBAL
##############################
echo "=== [1/5] Updating system and installing base packages ==="
apt-get update >>"$LOG_FILE" 2>&1
apt-get upgrade -y >>"$LOG_FILE" 2>&1

apt-get install --no-install-recommends -y \
  ca-certificates \
  curl \
  wget \
  git \
  nano \
  vim \
  net-tools \
  iproute2 \
  iputils-ping \
  rsyslog \
  sudo \
  tzdata \
  openssh-server >>"$LOG_FILE" 2>&1

########################################
# SSH STATUS + TAMPILKAN IP VM
########################################
echo "=== [INFO] SSH STATUS ==="
systemctl enable ssh >/dev/null 2>&1 || true
systemctl start ssh  >/dev/null 2>&1 || true

SSH_STATUS=$(systemctl is-active ssh || echo "unknown")
echo "SSH Service Status : $SSH_STATUS"

# Ambil IP utama (bukan docker, bukan loopback)
VM_IP=$(hostname -I | awk '{print $1}')
[ -z "$VM_IP" ] && VM_IP="(tidak terdeteksi)"

##############################
# INSTAL DVWA
##############################
echo "=== [2/5] Installing DVWA (Apache + PHP + MariaDB) ==="

# Install Apache + PHP + MariaDB untuk DVWA
apt-get install -y \
  apache2 \
  mariadb-server \
  mariadb-client \
  php \
  php-cli \
  php-mysql \
  php-gd \
  php-xml \
  php-curl \
  php-zip \
  libapache2-mod-php \
  git >>"$LOG_FILE" 2>&1

# Enable & start Apache + MariaDB
systemctl enable apache2 mariadb >>"$LOG_FILE" 2>&1 || true
systemctl start apache2 mariadb  >>"$LOG_FILE" 2>&1 || true

# Aktifkan mod PHP & rewrite (buat beberapa fitur DVWA)
a2enmod php* rewrite >>"$LOG_FILE" 2>&1 || true
systemctl restart apache2 >>"$LOG_FILE" 2>&1

# Clone DVWA ke /var/www/html/dvwa
if [ ! -d /var/www/html/dvwa ]; then
  echo "  -> Cloning DVWA..."
  git clone --depth=1 https://github.com/digininja/DVWA.git /var/www/html/dvwa >>"$LOG_FILE" 2>&1
else
  echo "  -> DVWA folder already exists, skip clone."
fi

cd /var/www/html/dvwa

# Copy default config kalau belum ada
if [ ! -f config/config.inc.php ]; then
  cp config/config.inc.php.dist config/config.inc.php
fi

echo "  -> Configuring MariaDB for DVWA..."
DB_NAME="dvwa"
DB_USER="dvwa"
DB_PASS="p@ssw0rd"   # <- password default DVWA

mysql -u root >>"$LOG_FILE" 2>&1 <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "  -> Setting DVWA permissions..."
chown -R www-data:www-data /var/www/html/dvwa
chmod -R 755 /var/www/html/dvwa
# folder upload harus writable
chmod 777 /var/www/html/dvwa/hackable/uploads || true

echo "  -> Configuring PHP for DVWA..."
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")
PHPINI="/etc/php/$PHP_VERSION/apache2/php.ini"
if [ -f "$PHPINI" ]; then
  sed -i 's/^\s*allow_url_include\s*=.*/allow_url_include = On/' "$PHPINI" || true
  sed -i 's/^\s*allow_url_fopen\s*=.*/allow_url_fopen = On/' "$PHPINI" || true
  sed -i 's/^\s*display_errors\s*=.*/display_errors = On/' "$PHPINI" || true
  sed -i 's/^\s*display_startup_errors\s*=.*/display_startup_errors = On/' "$PHPINI" || true
fi

systemctl restart apache2 >>"$LOG_FILE" 2>&1

echo "  -> DVWA installed."

##############################
# INSTAL SNORT3 + LIBDAQ + LIBML + EXTRA
##############################
echo "=== [3/5] Installing Snort3 and dependencies ==="

apt-get install --no-install-recommends -y \
  asciidoc \
  autoconf \
  automake \
  bison \
  build-essential \
  checkinstall \
  cmake \
  cpputest \
  dblatex \
  flex \
  g++ \
  gawk \
  gdb \
  jq \
  libcpputest-dev \
  libdnet-dev \
  libdumbnet-dev \
  libfl-dev \
  libflatbuffers-dev \
  libgoogle-perftools-dev \
  libhwloc-dev \
  libhyperscan-dev \
  libjemalloc-dev \
  libluajit-5.1-dev \
  liblzma-dev \
  libmnl-dev \
  libnetfilter-queue-dev \
  libnghttp2-dev \
  libpcap-dev \
  libpcre2-dev \
  libsafec-dev \
  libsqlite3-dev \
  libssl-dev \
  libtirpc-dev \
  libtool \
  libunwind-dev \
  make \
  netcat-openbsd \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv \
  tcpdump \
  uuid-dev \
  w3m \
  zlib1g-dev >>"$LOG_FILE" 2>&1

# user snorty
if ! id -u snorty >/dev/null 2>&1; then
  echo "  -> Creating user snorty:oink"
  useradd -m -s /bin/bash snorty
  echo "snorty:oink" | chpasswd
  usermod -aG sudo snorty
fi

echo "  -> Installing libdaq..."
rm -rf /tmp/libdaq
git clone https://github.com/snort3/libdaq.git /tmp/libdaq >>"$LOG_FILE" 2>&1
cd /tmp/libdaq
./bootstrap >>"$LOG_FILE" 2>&1
./configure --prefix=/usr/local >>"$LOG_FILE" 2>&1
make -j"$(nproc)" >>"$LOG_FILE" 2>&1
make install >>"$LOG_FILE" 2>&1
ldconfig >>"$LOG_FILE" 2>&1

echo "  -> Installing libml..."
rm -rf /tmp/libml
git clone https://github.com/snort3/libml.git /tmp/libml >>"$LOG_FILE" 2>&1
cd /tmp/libml
./configure.sh --prefix=/usr/local >>"$LOG_FILE" 2>&1
cd build
make -j"$(nproc)" >>"$LOG_FILE" 2>&1
make install >>"$LOG_FILE" 2>&1
ldconfig >>"$LOG_FILE" 2>&1
mkdir -p /usr/local/src/libml
cp -r /tmp/libml/examples /usr/local/src/libml/ >>"$LOG_FILE" 2>&1

echo "  -> Installing Snort3..."
rm -rf /tmp/snort3
git clone https://github.com/snort3/snort3.git /tmp/snort3 >>"$LOG_FILE" 2>&1
cd /tmp/snort3
./configure_cmake.sh --prefix=/usr/local --enable-debug-msgs >>"$LOG_FILE" 2>&1
cd build
make -j"$(nproc)" >>"$LOG_FILE" 2>&1
make install >>"$LOG_FILE" 2>&1
ldconfig >>"$LOG_FILE" 2>&1

echo "  -> Installing snort3_extra..."
rm -rf /tmp/snort3_extra
git clone https://github.com/snort3/snort3_extra.git /tmp/snort3_extra >>"$LOG_FILE" 2>&1
cd /tmp/snort3_extra
./configure_cmake.sh --prefix=/usr/local >>"$LOG_FILE" 2>&1
cd build
make -j"$(nproc)" >>"$LOG_FILE" 2>&1
make install >>"$LOG_FILE" 2>&1
ldconfig >>"$LOG_FILE" 2>&1

mkdir -p /var/log/snort
chmod 777 /var/log/snort

echo "  -> Snort3 install done. Binary: /usr/local/bin/snort"

##############################
# OPTIONAL: SERVICE SYSTEMD SNORT
##############################
echo "=== [4/5] Creating systemd service for Snort3 (interface: enp0s3) ==="

cat >/etc/systemd/system/snort.service <<EOF
[Unit]
Description=Snort 3 NIDS
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snort -c /usr/local/etc/snort/snort.lua -i enp0s3
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >>"$LOG_FILE" 2>&1
systemctl start snort >>"$LOG_FILE" 2>&1 || true
systemctl enable snort >>"$LOG_FILE" 2>&1 || true

##############################
# INSTAL WAZUH (ALL-IN-ONE)
##############################
echo "=== [5/5] Installing Wazuh all-in-one (manager + indexer + dashboard) ==="
cd /tmp
curl -sO https://packages.wazuh.com/4.8/wazuh-install.sh >>"$LOG_FILE" 2>&1
bash wazuh-install.sh -a | tee -a "$LOG_FILE"

echo "=== Wazuh installation script finished ==="

##############################
# RINGKASAN
##############################
echo
echo "========================================"
echo " INSTALLATION SUMMARY"
echo "========================================"
echo "SSH:"
echo "  Status   : $SSH_STATUS"
echo "  VM IP    : $VM_IP"
echo "  Login    : ssh <username>@$VM_IP"
echo
echo "DVWA:"
echo "  URL      : http://$VM_IP/dvwa"
echo "  DB user  : dvwa"
echo "  DB pass  : p@ssw0rd"
echo "  Web login: admin / password"
echo
echo "Snort3:"
echo "  Binary   : /usr/local/bin/snort"
echo "  Config   : /usr/local/etc/snort/snort.lua"
echo "  Log dir  : /var/log/snort"
echo "  Service  : systemctl status snort"
echo
echo "Wazuh:"
echo "  Dashboard: https://$VM_IP:443"
echo "  (Username/password awal ada di log Wazuh atau output instalasi)"
echo
echo "Log detail instalasi: $LOG_FILE"
echo "Silakan sesuaikan interface di /etc/systemd/system/snort.service jika bukan enp0s3."
echo "========================================"
