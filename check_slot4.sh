#!/usr/bin/env bash
# Inspect Slot 4 (PCIe Root Port 00:03.0) Details
# Run with: sudo ./check_slot4.sh

echo "========================================================"
echo "          PCIe Slot 4 Hardware Status Check             "
echo "========================================================"

PORT="0000:00:03.0"
SYSFS_PORT="/sys/bus/pci/devices/$PORT"

echo "[1] sysfs Link Status (Port 00:03.0 -> Physical Slot 4):"
if [ -d "$SYSFS_PORT" ]; then
    echo "  Power State:        $(cat $SYSFS_PORT/power_state 2>/dev/null)"
    echo "  Current Link Speed: $(cat $SYSFS_PORT/current_link_speed 2>/dev/null)"
    echo "  Current Link Width: $(cat $SYSFS_PORT/current_link_width 2>/dev/null)"
    echo "  Max Link Speed:     $(cat $SYSFS_PORT/max_link_speed 2>/dev/null)"
    echo "  Max Link Width:     $(cat $SYSFS_PORT/max_link_width 2>/dev/null)"
else
    echo "[-] Port $PORT not found in sysfs!"
fi

echo ""
echo "[2] Extended PCIe Capability (Requires root for full registers):"
if [ "$EUID" -ne 0 ]; then
    echo "  (Note: Run with 'sudo' to inspect hardware Presence Detect and LTSSM registers)"
    lspci -vvv -s 00:03.0 | grep -i -E 'slot|presence|link' || true
else
    lspci -vvv -s 00:03.0 | grep -i -E 'slot|presence|link|speed|width'
fi

echo ""
echo "[3] Secondary Bus 04 Devices:"
DEVICES=$(lspci -s 04: 2>/dev/null)
if [ -n "$DEVICES" ]; then
    echo "  Found devices on Bus 04:"
    echo "$DEVICES"
else
    echo "  [-] No devices responding on secondary bus 04."
fi
echo "========================================================"
