
#!/bin/bash
set -e
PROM_VER="2.43.0"

echo "=== [1/7] Пользователь/группа prometheus ==="
getent group prometheus >/dev/null || groupadd --system prometheus
id -u prometheus >/dev/null 2>&1 || useradd -s /sbin/nologin --system -g prometheus prometheus

echo "=== [2/7] Директории ==="
mkdir -p /etc/prometheus /var/lib/prometheus

echo "=== [3/7] Загрузка Prometheus ==="
cd /tmp
rm -rf prometheus-${PROM_VER}.linux-amd64 prometheus-${PROM_VER}.linux-amd64.tar.gz
wget -q https://github.com/prometheus/prometheus/releases/download/v${PROM_VER}/prometheus-${PROM_VER}.linux-amd64.tar.gz
tar xzf prometheus-${PROM_VER}.linux-amd64.tar.gz
cd prometheus-${PROM_VER}.linux-amd64

echo "=== [4/7] Копирование бинарников и файлов ==="
cp prometheus /usr/local/bin/
cp promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

cp -r consoles /etc/prometheus/
cp -r console_libraries /etc/prometheus/
cp prometheus.yml /etc/prometheus/prometheus.yml.orig
chown -R prometheus:prometheus /etc/prometheus/
chown -R prometheus:prometheus /var/lib/prometheus

echo "=== [5/7] Конфиг prometheus.yml ==="
cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 1s
  evaluation_interval: 1s
  scrape_timeout: 1s
  external_labels:
    monitor: 'gg-project'
scrape_configs:
  - job_name: "nginx"
    static_configs:
      - targets: ["127.0.0.1:9114"]
    metrics_path: "/metrics"
    scrape_interval: 1s
EOF
chown prometheus:prometheus /etc/prometheus/prometheus.yml

echo "=== [6/7] systemd service ==="
cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries
[Install]
WantedBy=multi-user.target
EOF

echo "=== [7/7] Запуск и проверка ==="
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
sleep 2
systemctl status prometheus --no-pager | head -n 10
systemctl status nginx-exporter.socket nginx-exporter.service --no-pager | head -n 16
echo "--- Открытые порты ---"
sudo ss -tlpn | grep -E ':9090|:9114|:80|:443'
echo "ГОТОВО. Откройте http://127.0.0.25:9090"
