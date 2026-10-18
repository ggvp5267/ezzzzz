
#!/bin/bash
set -e
HOST_NEW="ggServer"
USER_NEW="gg"
IP="192.168.25.250"
PREFIX="24"
GW="192.168.25.252"
DNS="185.11.79.5, 8.8.8.8"
IFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
echo ">>> Сетевой интерфейс: $IFACE"

# --- hostname ---
hostnamectl set-hostname "$HOST_NEW"
grep -q "$HOST_NEW" /etc/hosts || echo "127.0.1.1 $HOST_NEW" >> /etc/hosts

# --- пользователь с правами администратора ---
id "$USER_NEW" >/dev/null 2>&1 || useradd -m -s /bin/bash "$USER_NEW"
echo "${USER_NEW}:${USER_NEW}" | chpasswd
usermod -aG sudo "$USER_NEW"

# --- netplan: статический IP ---
cat > /etc/netplan/99-lan-interface.yaml <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${IP}/${PREFIX}]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${DNS}]
EOF
chmod 600 /etc/netplan/99-lan-interface.yaml

# остальные netplan-файлы убираем в бэкап, чтобы они не конфликтовали
mkdir -p /root/netplan-backup
for f in /etc/netplan/*.yaml; do
  [ "$f" = "/etc/netplan/99-lan-interface.yaml" ] || mv "$f" /root/netplan-backup/
done
# запрет cloud-init перегенерировать сеть
if [ -d /etc/cloud/cloud.cfg.d ]; then
  echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
fi

netplan generate
netplan apply
sleep 5

echo "=== ПРОВЕРКА ==="
hostnamectl | grep -i "static hostname"
ip -br a
ip r
ping -c2 192.168.25.252 || echo "!!! Router недоступен"
ping -c2 8.8.8.8        || echo "!!! Нет выхода в интернет через Router"
ping -c2 ubuntu.com     || echo "!!! DNS не работает"

