#!/usr/bin/env bash
# Real-time physical presence monitor for Slot 4
# Must be run with sudo

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    echo "Usage: sudo $0"
    exit 1
fi

PORT="0000:00:03.0"
echo on > "/sys/bus/pci/devices/$PORT/power/control" 2>/dev/null || true

echo "=========================================================="
echo "     Live Slot 4 Physical Presence Monitor (Ctrl+C to quit)"
echo "=========================================================="
echo "This monitors the motherboard's hardware presence detect"
echo "pin (PRSNT) in real-time as you inspect/seat the card."
echo ""

PREV=""
while true; do
    SLTSTA=$(setpci -s 00:03.0 CAP_EXP+1a.w 2>/dev/null)
    if [ -n "$SLTSTA" ]; then
        SLTSTA_DEC=$((0x$SLTSTA))
        PDS=$(( (SLTSTA_DEC >> 6) & 1 ))
        if [ "$PDS" -eq 1 ]; then
            if [ "$PREV" != "1" ]; then
                echo -e "\a" # Terminal beep
                echo -e "[$(date +%T)] \033[1;32m>>> SUCCESS: CARD DETECTED! (Slot Status: 0x$SLTSTA)\033[0m"
                echo "                 Physical electrical contact confirmed!"
                PREV="1"
            fi
        else
            if [ "$PREV" != "0" ]; then
                echo -e "[$(date +%T)] \033[1;31m[-] EMPTY: No electrical contact (Slot Status: 0x$SLTSTA)\033[0m"
                PREV="0"
            fi
        fi
    fi
    sleep 0.5
done
