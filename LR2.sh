#!/bin/bash
# ===========================================================================
# ЛР2 — Сервер HTTP Apache. Автоматическая настройка.
# Использование: sudo bash setup_lr2.sh фамилия gg
# ===========================================================================

set -e  # остановить скрипт при первой же ошибке

if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт через sudo: sudo bash setup_lr2.sh"
  exit 1
fi

echo "=== 1. Обновление системы ==="
apt update
apt upgrade -y

echo "=== 2. Установка и настройка apache2 ==="
apt install apache2 -y
systemctl enable apache2
systemctl start apache2
echo "--- Статус apache2 ---"
systemctl status apache2 --no-pager

echo "=== 3. Установка Juice Shop ==="
mkdir -p /opt/juiceshop
cd /opt/juiceshop
if [ ! -f "juice-shop-20.1.1_node24_linux_x64.tgz" ]; then
  wget https://github.com/juice-shop/juice-shop/releases/download/v20.1.1/juice-shop-20.1.1_node24_linux_x64.tgz
fi
tar -xvzf juice-shop-20.1.1_node24_linux_x64.tgz

echo "=== 4. Установка Node.js / NPM ==="
apt install npm -y

CURRENT_NODE_VER=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0)
if [ "$CURRENT_NODE_VER" -lt 24 ] 2>/dev/null; then
  echo "--- Версия Node ниже 24, устанавливаем через NVM ---"
  export NVM_DIR="/root/.nvm"
  wget -O- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
  . "$NVM_DIR/nvm.sh"
  nvm install 24
  nvm use 24
  NODE_BIN_PATH=$(dirname "$(readlink -f "$NVM_DIR/versions/node/$(nvm current)/bin/node")")
  cp "$NODE_BIN_PATH/node" /usr/bin/node
fi

echo "--- Версия node: $(node -v) ---"
echo "--- Версия npm: $(npm -v) ---"

echo "=== 5. Создание сервиса Juice Shop ==="
JUICESHOP_DIR=$(find /opt/juiceshop -maxdepth 1 -type d -name "juice-shop_*" | head -n1)
if [ -z "$JUICESHOP_DIR" ]; then
  echo "Не найдена распакованная папка juice-shop_*, проверь архив вручную."
  exit 1
fi

NPM_START_BIN=$(command -v npm || echo "/usr/bin/npm")

cat > /etc/systemd/system/juice-shop.service << EOF
[Unit]
Description=Application juiceshop in nodejs
After=network.target

[Service]
User=root
WorkingDirectory=${JUICESHOP_DIR}
ExecStart=${NPM_START_BIN} start

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start juice-shop.service
systemctl enable juice-shop.service
echo "--- Статус juice-shop.service ---"
systemctl status juice-shop.service --no-pager

echo "=== 6. Настройка доступа к Juice Shop через apache2 ==="
cat > /etc/apache2/sites-available/WebGg.conf << 'EOF'
<VirtualHost *:80>
    ServerName webgg.local
    ProxyRequests Off
    ProxyPreserveHost On
    <Proxy *>
        Order deny,allow
        Allow from all
    </Proxy>
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
    ErrorLog ${APACHE_LOG_DIR}/webgg_error.log
    CustomLog ${APACHE_LOG_DIR}/webgg_access.log combined
</VirtualHost>
EOF

a2enmod proxy proxy_http rewrite
a2dissite 000-default.conf || true
a2ensite WebGg.conf
apache2ctl configtest
systemctl restart apache2

echo "=== 7. Установка WebGoat ==="
apt install openjdk-17-jre -y
cd /opt
if [ ! -f "webgoat-2023.8.jar" ]; then
  wget https://github.com/WebGoat/WebGoat/releases/download/v2023.8/webgoat-2023.8.jar
fi
mkdir -p /var/webgoat
cp webgoat-2023.8.jar /var/webgoat/

cat > /etc/systemd/system/webgoat.service << 'EOF'
[Unit]
Description=webgoat server
After=network.target

[Service]
User=root
Environment="LOGGING_FILE_PATH=/var/webgoat/"
Environment="TZ=Europe/Minsk"
ExecStart=/usr/bin/java -jar /var/webgoat/webgoat-2023.8.jar

[Install]
WantedBy=multi-user.target
EOF

rm -f /var/www/html/index.html

systemctl daemon-reload
systemctl enable webgoat.service
systemctl start webgoat.service

echo "=== 8. Обновление конфига apache2 для WebGoat + Juice Shop ==="
cat > /etc/apache2/sites-enabled/WebGg.conf << 'EOF'
<VirtualHost *:80>
    ServerName webgg.local
    ProxyRequests Off
    ProxyPreserveHost On
    <Proxy *>
        Order deny,allow
        Allow from all
    </Proxy>
    ProxyPass /WebGoat http://127.0.0.1:8080/WebGoat
    ProxyPassReverse /WebGoat http://127.0.0.1:8080/WebGoat
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
    <Location /WebGoat>
        Order allow,deny
        Allow from all
    </Location>
    ErrorLog ${APACHE_LOG_DIR}/webgg_error.log
    CustomLog ${APACHE_LOG_DIR}/webgg_access.log combined
</VirtualHost>
EOF

apache2ctl configtest
systemctl restart apache2

echo ""
echo "==========================================================================="
echo "ГОТОВО. Проверь статусы служб и сделай скриншоты для отчёта:"
echo "  sudo systemctl status apache2"
echo "  sudo systemctl status juice-shop.service"
echo "  sudo systemctl status webgoat.service"
echo ""
echo "В браузере открой:"
echo "  http://192.168.25.251/           -> Juice Shop"
echo "  http://192.168.25.251/WebGoat/login  -> WebGoat"
echo "==========================================================================="
