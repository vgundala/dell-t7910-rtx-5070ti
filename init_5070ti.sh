#!/usr/bin/env bash
# Master initialization script for RTX 5070 Ti in Slot 4
# Must be run with sudo

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    echo "Usage: sudo $0"
    exit 1
fi

BRIDGE="0000:00:03.0"
GPU="0000:04:00.0"

echo "========================================================"
echo "        Initializing RTX 5070 Ti in Slot 4              "
echo "========================================================"

# 1. Wake Root Port
echo "[1] Waking Slot 4 PCIe Root Port ($BRIDGE)..."
echo on > "/sys/bus/pci/devices/$BRIDGE/power/control" 2>/dev/null || true
sleep 0.5

# 2. Check Link & Retrain if needed
WIDTH=$(cat "/sys/bus/pci/devices/$BRIDGE/current_link_width" 2>/dev/null)
if [ "$WIDTH" = "0" ] || [ -z "$WIDTH" ]; then
    echo "[2] Triggering PCIe Link Retrain..."
    setpci -s 00:03.0 CAP_EXP+10.w=0020:0020 2>/dev/null || true
    sleep 1.5
fi

# 3. Rescan PCIe Bus
echo "[3] Rescanning PCIe bus..."
if [ -f "/sys/bus/pci/devices/$BRIDGE/rescan" ]; then
    echo 1 > "/sys/bus/pci/devices/$BRIDGE/rescan"
fi
echo 1 > /sys/bus/pci/rescan
sleep 1.5

# 4. Program Bridge Windows
echo "[4] Programming hardware bridge decoding windows into $BRIDGE..."
# I/O window: 0x1000 - 0x1fff
setpci -s 00:03.0 1c.b=10
setpci -s 00:03.0 1d.b=10

# 32-bit MMIO: 0x50000000 - 0x540fffff
setpci -s 00:03.0 20.w=5000
setpci -s 00:03.0 22.w=5400

# 64-bit Prefetchable MMIO: 0x3010bf00000 - 0x3012fffffff
# Base: 0x0bf1 (0x3010bf00000), Limit: 0x2ff1 (0x3012fffffff)
setpci -s 00:03.0 24.w=0bf1
setpci -s 00:03.0 26.w=2ff1
setpci -s 00:03.0 28.l=00000301
setpci -s 00:03.0 2c.l=00000301

# Enable Bridge Bus Mastering, Memory, and I/O forwarding
setpci -s 00:03.0 04.w=0407:0407

# 5. Enable GPU Bus Mastering and Memory
if [ -d "/sys/bus/pci/devices/$GPU" ]; then
    echo "[5] Enabling Bus Master & Memory on GPU ($GPU)..."
    setpci -s 04:00.0 04.w=0007:0007 2>/dev/null || true
fi

# 6. Load Modules & Bind Driver
echo "[6] Loading NVIDIA modules and re-binding driver..."
modprobe nvidia 2>/dev/null || true
modprobe nvidia_uvm 2>/dev/null || true
modprobe nvidia_modeset 2>/dev/null || true
modprobe nvidia_drm 2>/dev/null || true

if [ -d "/sys/bus/pci/devices/$GPU/driver" ]; then
    echo "$GPU" > "/sys/bus/pci/devices/$GPU/driver/unbind" 2>/dev/null || true
    sleep 0.5
fi

if [ -d /sys/bus/pci/drivers/nvidia ]; then
    echo "$GPU" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
fi

sleep 1.5

# 7. Check Status
echo ""
echo "[7] Final Status:"
lspci -k -s 04:00.0
echo ""
echo "Running nvidia-smi:"
nvidia-smi
echo "========================================================"
