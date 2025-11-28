#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini butuh akses root. Jalankan dengan: sudo bash install-windows11-cloudflare.sh"
  exit 1
fi

apt update -y
apt install docker-compose -y

systemctl enable docker
systemctl start docker

mkdir -p /root/dockercom
cd /root/dockercom

cat > windows.yml <<'EOF'
version: "3.9"
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"
      USERNAME: "MASTER"
      PASSWORD: "admin@123"
      RAM_SIZE: "16G"
      CPU_CORES: "8"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - /tmp/windows-storage:/storage
    restart: always
    stop_grace_period: 2m

EOF

cat windows.yml

docker-compose -f windows.yml up -d

echo "Menghentikan Windows container untuk konfigurasi Tailscale..."
docker stop windows

WIN_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' windows)
TAILSCALE_AUTHKEY="YOUR_TAILSCALE_AUTH_KEY_HERE"

docker run -d \
  --name tailscale \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -e TS_STATE_DIR=/var/lib/tailscale \
  -v /var/lib/tailscale:/var/lib/tailscale \
  -v /dev/net/tun:/dev/net/tun \
  -e TS_AUTHKEY="$TAILSCALE_AUTHKEY" \
  --network=host \
  tailscale/tailscale \
  /bin/sh -c 'tailscaled & sleep 5; tailscale up --authkey=$TS_AUTHKEY --hostname=windows-vm-host --advertise-routes=${WIN_IP}/32'
  
docker start windows

if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

nohup cloudflared tunnel --url http://localhost:8006 > /var/log/cloudflared_web.log 2>&1 &
nohup cloudflared tunnel --url tcp://localhost:3389 > /var/log/cloudflared_rdp.log 2>&1 &
sleep 6

CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
CF_RDP=$(grep -o "tcp://[a-zA-Z0-9.-]*\.trycloudflare\.com:[0-9]*" /var/log/cloudflared_rdp.log | head -n 1)

echo
echo "=============================================="
echo "🎉 Instalasi Selesai!"
echo
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console (NoVNC / UI):"
  echo "    ${CF_WEB}"
else
  echo "⚠️ Tidak menemukan link web Cloudflare (port 8006)"
  echo "    Cek log: tail -f /var/log/cloudflared_web.log"
fi

if [ -n "$CF_RDP" ]; then
  echo
  echo "🖥️  Remote Desktop (RDP) melalui Cloudflare:"
  echo "    ${CF_RDP}"
else
  echo "⚠️ Tidak menemukan link RDP Cloudflare (port 3389)"
  echo "    Cek log: tail -f /var/log/cloudflared_rdp.log"
fi

echo
echo "🔑 Username: MASTER"
echo "🔒 Password: admin@123"
echo
echo "Untuk melihat status container:"
echo "  docker ps"
echo
echo "Untuk menghentikan VM:"
echo "  docker stop windows"
echo
echo "Untuk melihat log Windows:"
echo "  docker logs -f windows"
echo
echo "Untuk melihat link Cloudflare:"
echo "  grep 'trycloudflare' /var/log/cloudflared_*.log"
echo
echo "=============================================="