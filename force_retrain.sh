#!/usr/bin/env bash
# Hardware PCIe Link Retrain & Diagnostic for Slot 4
# Must be run with sudo

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    echo "Usage: sudo $0"
    exit 1
fi

PORT="0000:00:03.0"
SYSFS_PORT="/sys/bus/pci/devices/$PORT"

echo "========================================================"
echo "        PCIe Slot 4 Hardware Retrain & Diagnostics      "
echo "========================================================"

echo "[1] Ensuring Root Port $PORT is powered ON (D0)..."
echo on > "$SYSFS_PORT/power/control" 2>/dev/null || true
sleep 0.5

echo ""
echo "[2] Slot & Link Status from lspci:"
lspci -vvv -s 00:03.0 | grep -i -E 'slot status|slot cap|link sta|link ctl' | grep -v 'Dev' || true

echo ""
echo "[3] Checking Physical Presence Detect State:"
SLTSTA=$(setpci -s 00:03.0 CAP_EXP+1a.w 2>/dev/null)
if [ -n "$SLTSTA" ]; then
    SLTSTA_DEC=$((0x$SLTSTA))
    PDS=$(( (SLTSTA_DEC >> 6) & 1 ))
    echo "  Raw Slot Status: 0x$SLTSTA"
    if [ "$PDS" -eq 1 ]; then
        echo "  >>> Presence Detect State: 1 (CARD PHYSICALLY DETECTED IN SLOT!)"
    else
        echo "  [-] Presence Detect State: 0 (Motherboard PRSNT pin reads EMPTY / OPEN)"
    fi
fi

echo ""
echo "[4] Triggering Hardware PCIe Link Retrain..."
# Bit 5 of LnkCtl is Retrain Link (0x0020)
setpci -s 00:03.0 CAP_EXP+10.w=0020:0020 2>/dev/null || true
sleep 1.5

WIDTH=$(cat "$SYSFS_PORT/current_link_width" 2>/dev/null)
SPEED=$(cat "$SYSFS_PORT/current_link_speed" 2>/dev/null)
echo "  Post-retrain Link Width: $WIDTH"
echo "  Post-retrain Link Speed: $SPEED"

echo ""
echo "[5] Rescanning PCIe Bus..."
if [ -f "$SYSFS_PORT/rescan" ]; then
    echo 1 > "$SYSFS_PORT/rescan"
fi
echo 1 > /sys/bus/pci/rescan
sleep 1.5

echo ""
echo "[6] Checking for NVIDIA GPU:"
NVIDIA=$(lspci -nn | grep -i "10de:")
if [ -n "$NVIDIA" ]; then
    echo ">>> SUCCESS! Found NVIDIA Device:"
    echo "$NVIDIA"
    echo ""
    echo "Checking nvidia-smi:"
    nvidia-smi || true
else
    echo "[-] No NVIDIA device responded."
    echo "    Current Link Width: $(cat $SYSFS_PORT/current_link_width 2>/dev/null)"
fi
echo "========================================================"
