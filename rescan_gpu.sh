#!/usr/bin/env bash
# Rescan PCIe bus to wake Slot 4 and detect RTX 5070 Ti
# Must be run with sudo

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    echo "Usage: sudo $0"
    exit 1
fi

echo "========================================================"
echo "         Waking Slot 4 & Rescanning PCIe Bus            "
echo "========================================================"

PORT="0000:00:03.0"

echo "[1] Current state of Port $PORT (Slot 4):"
echo "  Power State:    $(cat /sys/bus/pci/devices/$PORT/power_state 2>/dev/null)"
echo "  Runtime Status: $(cat /sys/bus/pci/devices/$PORT/power/runtime_status 2>/dev/null)"
echo "  Link Width:     $(cat /sys/bus/pci/devices/$PORT/current_link_width 2>/dev/null)"
echo "  Link Speed:     $(cat /sys/bus/pci/devices/$PORT/current_link_speed 2>/dev/null)"

echo ""
echo "[2] Forcing Slot 4 power control to 'on' (waking from D3hot)..."
echo on > /sys/bus/pci/devices/$PORT/power/control
sleep 1

echo "[3] Rescanning Port $PORT and all PCIe buses..."
if [ -f /sys/bus/pci/devices/$PORT/rescan ]; then
    echo 1 > /sys/bus/pci/devices/$PORT/rescan
fi
echo 1 > /sys/bus/pci/rescan
sleep 2

echo ""
echo "[4] Checking PCIe bus for NVIDIA devices:"
NVIDIA=$(lspci -nn | grep -i "10de:")
if [ -n "$NVIDIA" ]; then
    echo ">>> SUCCESS! Found NVIDIA Device:"
    echo "$NVIDIA"
    echo ""
    echo "[5] Checking bridge memory decoding window:"
    lspci -v -s 00:03.0 | grep -i "behind bridge" || true
    echo ""
    echo "[6] Checking driver attachment:"
    if [ ! -d /sys/bus/pci/devices/0000:04:00.0/driver ]; then
        echo "  Driver not attached yet. Triggering modprobe and bind..."
        modprobe nvidia 2>/dev/null || true
        if [ -f /sys/bus/pci/drivers/nvidia/bind ]; then
            echo "0000:04:00.0" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
        fi
        sleep 1
    fi
    echo ""
    echo "[7] Running nvidia-smi:"
    nvidia-smi || true
else
    echo "[-] NVIDIA hardware not yet responding on PCIe bus."
    echo "Current Slot 4 link status:"
    echo "  Link Width: $(cat /sys/bus/pci/devices/$PORT/current_link_width 2>/dev/null)"
    echo "  Link Speed: $(cat /sys/bus/pci/devices/$PORT/current_link_speed 2>/dev/null)"
fi

echo "========================================================"
