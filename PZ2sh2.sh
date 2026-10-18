
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
DB_NAME="wordpress"; DB_USER="gg"; DB_PASS="gg"; MYSQL_ROOT_PASS="ubuntu"
DOMAIN="gg.bsuir.lab"

echo "=== [1/6] Nginx ==="
apt-get update
apt-get install -y nginx wget unzip curl
systemctl enable nginx
systemctl start nginx

echo "=== [2/6] MySQL ==="
apt-get install -y mysql-server mysql-client
systemctl enable mysql
systemctl start mysql
if mysql -uroot -e "SELECT 1" >/dev/null 2>&1; then MYSQL_CMD="mysql -uroot"; else MYSQL_CMD="mysql -uroot -p${MYSQL_ROOT_PASS}"; fi
$MYSQL_CMD <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
SQL

echo "=== [3/6] PHP ==="
# сначала php-fpm, чтобы apt не потянул apache2
apt-get install -y php-fpm php-cli php-gd php-mysql php-zip php-xml php-mbstring php-curl php-intl
apt-get install -y php
systemctl disable --now apache2 2>/dev/null || true
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo "Версия PHP: $PHPV"
cat > /etc/php/${PHPV}/fpm/conf.d/99-wp-upload.ini <<EOF
upload_max_filesize = 64M
post_max_size = 64M
memory_limit = 256M
EOF
systemctl enable php${PHPV}-fpm
systemctl restart php${PHPV}-fpm

echo "=== [4/6] WordPress ==="
cd /tmp
rm -rf wordpress latest.zip
wget -q https://wordpress.org/latest.zip
unzip -q latest.zip
rm -f /var/www/html/index.nginx-debian.html
cp -r wordpress/* /var/www/html/
chown -R www-data:www-data /var/www/html/

echo "=== [5/6] Конфиг Nginx (HTTP) ==="
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;
    server_name __DOMAIN__ _;
    client_max_body_size 64M;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # pass PHP scripts to FastCGI server
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php__PHPV__-fpm.sock;
    }

    # deny access to .htaccess files
    location ~ /\.ht {
        deny all;
    }
}
EOF
sed -i "s/__DOMAIN__/$DOMAIN/g; s/__PHPV__/$PHPV/g" /etc/nginx/sites-available/default
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

echo "=== [6/6] СТАТУСЫ (для отчёта) ==="
systemctl status nginx --no-pager | head -n 8
systemctl status mysql --no-pager | head -n 8
systemctl status php${PHPV}-fpm --no-pager | head -n 8
curl -sI http://localhost | head -n 5
echo "ГОТОВО. Теперь откройте в браузере хоста http://127.0.0.25"

