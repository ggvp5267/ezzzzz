
#!/bin/bash
set -e
DOMAIN="gg.bsuir.lab"
SERVER_IP="192.168.25.250"
DAYS=730          # 2 года
DH_BITS=4096
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

echo "=== [1/5] Ключ и самоподписанный сертификат ==="
openssl req -x509 -nodes -days $DAYS -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj "/C=BY/ST=Minsk/L=Minsk/O=BSUIR/OU=IS/CN=${DOMAIN}/emailAddress=gg@mail.bu" \
  -addext "subjectAltName=DNS:${DOMAIN},IP:${SERVER_IP}"
chmod 600 /etc/ssl/private/nginx-selfsigned.key

echo "=== [2/5] Параметры Диффи-Хеллмана (долго!) ==="
[ -f /etc/nginx/dhparam.pem ] || openssl dhparam -out /etc/nginx/dhparam.pem $DH_BITS

echo "=== [3/5] Сниппеты ==="
mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/self-signed.conf <<'EOF'
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOF

cat > /etc/nginx/snippets/ssl-params.conf <<'EOF'
ssl_protocols TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_dhparam /etc/nginx/dhparam.pem;
ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 185.11.79.5 8.8.8.8 valid=300s;
resolver_timeout 5s;
# Disable strict transport security for now.
#add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options SAMEORIGIN;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOF

echo "=== [4/5] Конфиг сервера ==="
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    #LISTEN#
    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;

    server_name __DOMAIN__ _;
    root /var/www/html;
    index index.php index.html index.htm;
    client_max_body_size 64M;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php__PHPV__-fpm.sock;
    }
    location ~ /\.ht {
        deny all;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__ _;
    return 302 https://$host$request_uri;
}
EOF
NGV=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ "$(printf '%s\n%s\n' 1.25.1 "$NGV" | sort -V | head -1)" = "1.25.1" ]; then
  L='listen 443 ssl default_server;\n    listen [::]:443 ssl default_server;\n    http2 on;'
else
  L='listen 443 ssl http2 default_server;\n    listen [::]:443 ssl http2 default_server;'
fi
sed -i "s|#LISTEN#|$L|; s/__DOMAIN__/$DOMAIN/g; s/__PHPV__/$PHPV/g" /etc/nginx/sites-available/default
nginx -t
systemctl restart nginx

echo "=== [5/5] Перевод WordPress на https://$DOMAIN ==="
if [ -f /var/www/html/wp-config.php ]; then
  curl -sSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x /usr/local/bin/wp
  NEW="https://${DOMAIN}"
  OLD=$(wp --allow-root --path=/var/www/html option get siteurl 2>/dev/null || true)
  echo "Старый URL: $OLD -> новый: $NEW"
  if [ -n "$OLD" ] && [ "$OLD" != "$NEW" ]; then
    wp --allow-root --path=/var/www/html search-replace "$OLD" "$NEW" --all-tables --skip-columns=guid
    wp --allow-root --path=/var/www/html search-replace "${OLD//\//\\/}" "${NEW//\//\\/}" --all-tables --skip-columns=guid || true
  fi
  chown -R www-data:www-data /var/www/html
else
  echo "WordPress ещё не установлен (нет wp-config.php), пропускаю."
fi
echo "ГОТОВО. Открывайте https://$DOMAIN"

