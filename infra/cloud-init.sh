#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/exemplifi_bootstrap.log
exec > >(tee -a "$LOG") 2>&1

echo "[*] Starting bootstrap at $(date)"

# --- Variables (change only if you know what you're doing) ---
DB_ROOT_PASSWORD='Exemplifi@#$123'
WP_DB_NAME='wp'
WP_DB_USER='wpuser'
WP_DB_PASSWORD='' # will generate if empty
SITE_TITLE='Exemplifi WebOps'
ADMIN_USER='nimda'
ADMIN_PASSWORD='Exemplifi123@#$'
ADMIN_EMAIL='admin@example.com'

if [ -z "${WP_DB_PASSWORD}" ]; then
  WP_DB_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24 || true)
fi

echo "[*] Apt update & base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 mariadb-server \
  php php-mysql php-xml php-gd php-curl php-mbstring php-zip unzip curl jq \
  ufw fail2ban unattended-upgrades ca-certificates openssl rsync

# --- SSH hardening (port 2222, no root login, no password auth) ---
echo "[*] SSH hardening"
sed -i 's/^#*Port .*/Port 2222/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd || true

# --- UFW (optional but good) ---
if command -v ufw >/dev/null 2>&1; then
  ufw --force reset
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 2222/tcp
  ufw --force enable || true
fi

# --- MariaDB secure setup ---
echo "[*] Securing MariaDB"
# Bind to localhost only
sed -i 's/^\s*bind-address\s*=.*$/bind-address = 127.0.0.1/' /etc/mysql/mariadb.conf.d/50-server.cnf || true
systemctl enable --now mariadb

# Run secure setup via SQL (idempotent)
mysql --user=root <<SQL
-- Set root password & auth
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${DB_ROOT_PASSWORD}');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

# Create WP database and user (idempotent)
mysql --user=root --password="${DB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${WP_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'localhost' IDENTIFIED BY '${WP_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${WP_DB_NAME}\`.* TO '${WP_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# --- Apache + PHP + SSL ---
echo "[*] Apache config & SSL"
a2enmod rewrite ssl headers

# Self-signed cert (1 year)
if [ ! -f /etc/ssl/private/wp.key ]; then
  openssl req -x509 -nodes -days 365 \
    -subj "/C=IN/ST=KA/L=Bengaluru/O=Exemplifi/OU=WebOps/CN=localhost" \
    -newkey rsa:2048 -keyout /etc/ssl/private/wp.key -out /etc/ssl/certs/wp.crt
  chmod 600 /etc/ssl/private/wp.key
fi

# HTTP -> HTTPS redirect vhost
cat >/etc/apache2/sites-available/000-default.conf <<'VHOST'
<VirtualHost *:80>
  ServerName _
  Redirect permanent / https://%{HTTP_HOST}%{REQUEST_URI}
</VirtualHost>
VHOST

# HTTPS vhost with env vars for DB (kept on server, not in git)
cat >/etc/apache2/sites-available/wordpress-ssl.conf <<VHOST
<VirtualHost *:443>
  ServerName _
  DocumentRoot /var/www/html

  SSLEngine on
  SSLCertificateFile /etc/ssl/certs/wp.crt
  SSLCertificateKeyFile /etc/ssl/private/wp.key

  <Directory /var/www/html>
    AllowOverride All
    Require all granted
  </Directory>

  # Security headers
  Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

  # WordPress DB env (no secrets in git)
  SetEnv WP_DB_NAME     ${WP_DB_NAME}
  SetEnv WP_DB_USER     ${WP_DB_USER}
  SetEnv WP_DB_PASSWORD ${WP_DB_PASSWORD}
  SetEnv WP_DB_HOST     127.0.0.1
</VirtualHost>
VHOST

a2ensite wordpress-ssl.conf
systemctl reload apache2 || systemctl restart apache2
systemctl enable apache2

# --- WordPress install ---
echo "[*] Installing WordPress"
cd /tmp
curl -fsSLO https://wordpress.org/latest.zip
unzip -o latest.zip
rsync -a wordpress/ /var/www/html/

# wp-config using env vars
if [ ! -f /var/www/html/wp-config.php ]; then
  cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
  php -r '
    $f = "/var/www/html/wp-config.php";
    $s = file_get_contents($f);
    $s = preg_replace("/define\\(\\s*\\x27DB_NAME\\x27.*;/","define(\\x27DB_NAME\\x27, getenv(\\x27WP_DB_NAME\\x27) ?: \\x27wp\\x27 );",$s);
    $s = preg_replace("/define\\(\\s*\\x27DB_USER\\x27.*;/","define(\\x27DB_USER\\x27, getenv(\\x27WP_DB_USER\\x27) ?: \\x27wpuser\\x27 );",$s);
    $s = preg_replace("/define\\(\\s*\\x27DB_PASSWORD\\x27.*;/","define(\\x27DB_PASSWORD\\x27, getenv(\\x27WP_DB_PASSWORD\\x27) ?: \\x27\\x27 );",$s);
    $s = preg_replace("/define\\(\\s*\\x27DB_HOST\\x27.*;/","define(\\x27DB_HOST\\x27, getenv(\\x27WP_DB_HOST\\x27) ?: \\x27127.0.0.1\\x27 );",$s);
    file_put_contents($f,$s);
  '
fi

# Permissions
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# WP-CLI for automated install
if ! command -v wp >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
  chmod +x /usr/local/bin/wp
fi

# Discover our public URL (best effort)
PUB_IP=$(curl -fsS http://checkip.amazonaws.com || echo "localhost")
sudo -u www-data wp core install --path=/var/www/html \
  --url="https://${PUB_IP}/" \
  --title="${SITE_TITLE}" \
  --admin_user="${ADMIN_USER}" \
  --admin_password="${ADMIN_PASSWORD}" \
  --admin_email="${ADMIN_EMAIL}" || true

# Pretty permalinks (optional)
sudo -u www-data wp rewrite structure '/%postname%/' --hard --path=/var/www/html || true

# --- fail2ban ---
echo "[*] Configuring fail2ban"
cat >/etc/fail2ban/jail.d/sshd.local <<'JAIL'
[sshd]
enabled = true
port = 2222
bantime = 1h
findtime = 10m
maxretry = 5
JAIL
systemctl enable --now fail2ban

# --- Unattended upgrades ---
echo "[*] Enabling unattended-upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades || true
systemctl enable --now unattended-upgrades

echo "[*] Done at $(date)"
