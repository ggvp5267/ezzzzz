
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== [1/6] snapd и nginx-prometheus-exporter ==="
apt-get update
apt-get install -y snapd
systemctl enable --now snapd.socket snapd.service
sleep 3
# на некоторых ядрах snap требует перезахода - на всякий случай создаём симлинк заранее
ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
snap install core 2>/dev/null || true
snap install nginx-prometheus-exporter

echo "=== [2/6] Файл metrics (stub_status на 127.0.0.1:8080) ==="
cat > /etc/nginx/sites-enabled/metrics <<'EOF'
server {
    listen 127.0.0.1:8080;
    server_name _;
    location /stub_status {
        stub_status;
    }
}
EOF
nginx -t
systemctl reload nginx

echo "=== [3/6] Пользователь/группа nginx_exporter ==="
getent group nginx_exporter >/dev/null || groupadd --system nginx_exporter
id -u nginx_exporter >/dev/null 2>&1 || useradd -s /sbin/nologin --system -g nginx_exporter nginx_exporter
mkdir -p /home/nginx_exporter
chown -R nginx_exporter:nginx_exporter /home/nginx_exporter

echo "=== [4/6] systemd: socket + service ==="
cat > /etc/systemd/system/nginx-exporter.socket <<'EOF'
[Unit]
Description=NGINX Prometheus Exporter
[Socket]
ListenStream=0.0.0.0:9114
[Install]
WantedBy=sockets.target
EOF

EXPORTER_BIN=/snap/bin/nginx-prometheus-exporter
cat > /etc/systemd/system/nginx-exporter.service <<EOF
[Unit]
Description=NGINX Prometheus Exporter
Requires=nginx-exporter.socket
[Service]
User=nginx_exporter
ExecStart=${EXPORTER_BIN} --nginx.scrape-uri=http://127.0.0.1:8080/stub_status --web.systemd-socket
[Install]
WantedBy=multi-user.target
EOF

echo "=== [5/6] Запуск ==="
systemctl daemon-reload
systemctl enable nginx-exporter.socket nginx-exporter.service
systemctl start nginx-exporter.socket nginx-exporter.service
sleep 2

echo "=== [6/6] ПРОВЕРКА ==="
systemctl status nginx-exporter.socket --no-pager | head -n 8
systemctl status nginx-exporter.service --no-pager | head -n 8
echo "--- stub_status ---"
curl -s http://127.0.0.1:8080/stub_status
echo "--- metrics (первые строки) ---"
curl -s http://127.0.0.1:9114/metrics | head -n 15
