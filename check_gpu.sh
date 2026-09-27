#!/usr/bin/env bash
# Hardware and Driver Diagnostic Script for RTX 5070 Ti on Dell Precision T7910

echo "=== 1. Checking PCIe Bus for NVIDIA Devices (Vendor ID: 10de) ==="
NVIDIA_DEVICES=$(lspci -nn | grep -i "10de:")
if [ -n "$NVIDIA_DEVICES" ]; then
    echo "Found NVIDIA hardware on PCIe bus:"
    echo "$NVIDIA_DEVICES"
else
    echo "[-] NO NVIDIA hardware detected on PCIe bus."
    echo "    (The motherboard/BIOS has not detected the card yet)"
fi

echo ""
echo "=== 2. All Display / VGA Controllers Detected ==="
lspci -nn | grep -i -E 'vga|3d|display'

echo ""
echo "=== 3. NVIDIA Kernel Modules ==="
lsmod | grep -i nvidia || echo "[-] NVIDIA kernel modules not loaded"

echo ""
echo "=== 4. nvidia-smi Status ==="
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi 2>&1 || true
else
    echo "[-] nvidia-smi not installed or not in PATH"
fi

echo ""
echo "=== 5. Recent Kernel / NVRM Messages ==="
journalctl -b -k --no-pager -n 50 2>&1 | grep -i -E 'nvidia|nvrm' | tail -n 10 || true
