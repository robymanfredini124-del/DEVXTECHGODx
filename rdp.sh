#!/bin/bash
set -e

echo "=== Running as root ==="
if [ "$EUID" -ne 0 ]; then
  echo "Run as: sudo bash install-windows11.sh"
  exit 1
fi

apt update -y
apt install docker-compose wget -y
systemctl enable docker
systemctl start docker

mkdir -p /root/dockercom
cd /root/dockercom

echo "=== Creating windows.yml ==="
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
      RAM_SIZE: "7G"
      CPU_CORES: "4"
      RDP_PUBLIC: "true"
      INSTALL_TAILSCALE: "true"
      TAILSCALE_AUTHKEY: "tskey-auth-kM6Ky2w5PW11CNTRL-E6wZvLeksFPh2Mqm8pckFP7kB16QsPNd"
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

echo "=== Starting Windows container ==="
docker-compose -f windows.yml up -d

echo
echo "=== Installing Cloudflare Tunnel ==="
if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

nohup cloudflared tunnel --url http://localhost:8006 > /var/log/cloudflared_web.log 2>&1 &
nohup cloudflared tunnel --url tcp://localhost:3389 > /var/log/cloudflared_rdp.log 2>&1 &
sleep 6

CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
CF_RDP=$(grep -o "tcp://[a-zA-Z0-9.-]*\.trycloudflare\.com:[0-9]*" /var/log/cloudflared_rdp.log | head -n 1)

echo "---------------------------------------------------"
echo " Installation Complete!"
echo
echo " NoVNC Web UI:"
echo "   ${CF_WEB}"
echo
echo " RDP via Cloudflare TCP:"
echo "   ${CF_RDP}"
echo
echo " Username: MASTER"
echo " Password: admin@123"
echo
echo " To stop VM:  docker stop windows"
echo "---------------------------------------------------"
echo "  docker logs -f windows"
echo
echo "Untuk melihat link Cloudflare:"
echo "  grep 'trycloudflare' /var/log/cloudflared_*.log"
echo
echo "=============================================="
