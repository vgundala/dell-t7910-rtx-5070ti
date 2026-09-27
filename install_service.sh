#!/usr/bin/env bash
# Install RTX 5070 Ti boot and monitor services into systemd
# Must be run with sudo

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    echo "Usage: sudo $0"
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================"
echo "    Installing RTX 5070 Ti Systemd Services            "
echo "========================================================"

# 1. Install Scripts to /usr/local/bin
echo "[1] Installing scripts to /usr/local/bin..."
cp "$DIR/init_gpu_boot.sh" /usr/local/bin/init_gpu_boot.sh
chmod 755 /usr/local/bin/init_gpu_boot.sh

cp "$DIR/gpu_presence_monitor.py" /usr/local/bin/gpu_presence_monitor.py
chmod 755 /usr/local/bin/gpu_presence_monitor.py

# 2. Install Boot Initialization Service
echo "[2] Installing init-5070ti.service..."
cp "$DIR/init-5070ti.service" /etc/systemd/system/
chmod 644 /etc/systemd/system/init-5070ti.service
systemctl enable init-5070ti.service

# 3. Install Real-time Presence Monitor Service
echo "[3] Installing gpu-presence-monitor.service..."
cp "$DIR/gpu-presence-monitor.service" /etc/systemd/system/
chmod 644 /etc/systemd/system/gpu-presence-monitor.service
systemctl enable gpu-presence-monitor.service

# 4. Reload systemd daemon and restart monitor
echo "[4] Reloading systemd..."
systemctl daemon-reload
systemctl restart gpu-presence-monitor.service

echo ""
echo ">>> SUCCESS! Both services are installed and active:"
echo "    1. init-5070ti.service        -> Auto-initializes GPU on every system boot."
echo "    2. gpu-presence-monitor.service -> Monitors physical pin seating in real time."
echo "                                     Shows persistent alert if pins lift."
echo "                                     Notifies when contact is restored."
echo "========================================================"
