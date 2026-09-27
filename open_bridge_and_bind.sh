#!/usr/bin/env bash
# Open PCIe Bridge Windows on Port 00:03.0 and Bind NVIDIA Driver
# Must be run with sudo

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo."
    echo "Usage: sudo $0"
    exit 1
fi

BRIDGE="0000:00:03.0"
GPU="0000:04:00.0"

echo "========================================================"
echo "    Configuring Hardware Bridge Windows for Slot 4     "
echo "========================================================"

echo "[1] Checking current raw bridge config registers:"
python3 -c "
with open('/sys/bus/pci/devices/$BRIDGE/config', 'rb') as f:
    cfg = f.read(64)
    mem_base = int.from_bytes(cfg[0x20:0x22], 'little') << 16
    mem_limit = (int.from_bytes(cfg[0x22:0x24], 'little') << 16) | 0xfffff
    print(f'  Pre-fix Mem Base-Limit: 0x{mem_base:08x} - 0x{mem_limit:08x}')
"

echo ""
echo "[2] Programming hardware bridge decoding windows into $BRIDGE:"
# I/O window: 0x1000 - 0x1fff
setpci -s 00:03.0 1c.b=10
setpci -s 00:03.0 1d.b=10

# 32-bit Memory window: 0x50000000 - 0x540fffff
setpci -s 00:03.0 20.w=5000
setpci -s 00:03.0 22.w=5400

# 64-bit Prefetchable Memory window: 0x3010bf00000 - 0x3012fffffff
setpci -s 00:03.0 24.w=bf01
setpci -s 00:03.0 26.w=2ff1
setpci -s 00:03.0 28.l=00000301
setpci -s 00:03.0 2c.l=00000301

# Enable Bridge Bus Mastering, Memory, and I/O forwarding
setpci -s 00:03.0 04.w=0407:0407

# Enable GPU Bus Mastering, Memory, and I/O
setpci -s 04:00.0 04.w=0007:0007

echo ""
echo "[3] Verifying new bridge config registers:"
python3 -c "
with open('/sys/bus/pci/devices/$BRIDGE/config', 'rb') as f:
    cfg = f.read(64)
    mem_base = int.from_bytes(cfg[0x20:0x22], 'little') << 16
    mem_limit = (int.from_bytes(cfg[0x22:0x24], 'little') << 16) | 0xfffff
    pref_base = (int.from_bytes(cfg[0x28:0x2c], 'little') << 32) | (int.from_bytes(cfg[0x24:0x26], 'little') & 0xfff0) << 16
    pref_limit = (int.from_bytes(cfg[0x2c:0x30], 'little') << 32) | (int.from_bytes(cfg[0x26:0x28], 'little') & 0xfff0) << 16 | 0xfffff
    print(f'  >>> Fixed Mem Base-Limit:  0x{mem_base:08x} - 0x{mem_limit:08x}')
    print(f'  >>> Fixed Pref Base-Limit: 0x{pref_base:012x} - 0x{pref_limit:012x}')
"

echo ""
echo "[4] Testing MMIO read access to GPU BAR0 (NV_PMC_BOOT_0):"
python3 -c "
try:
    with open('/sys/bus/pci/devices/$GPU/resource0', 'rb') as f:
        data = f.read(16)
        print('  BAR0 first 16 bytes:', data.hex())
        val = int.from_bytes(data[:4], 'little')
        if val == 0xffffffff:
            print('  [-] WARNING: Still returning 0xFFFFFFFF (master abort / not forwarded)')
        else:
            print(f'  >>> SUCCESS! Hardware signature read: 0x{val:08x}')
except Exception as e:
    print('  Error reading resource0:', e)
"

echo ""
echo "[5] Binding GPU to NVIDIA driver..."
# If driver not loaded, load it
modprobe nvidia 2>/dev/null || true
modprobe nvidia_drm 2>/dev/null || true
modprobe nvidia_modeset 2>/dev/null || true
modprobe nvidia_uvm 2>/dev/null || true

# Trigger driver re-bind
if [ -d /sys/bus/pci/drivers/nvidia ]; then
    if [ -d /sys/bus/pci/devices/$GPU/driver ]; then
        echo "$GPU" > /sys/bus/pci/devices/$GPU/driver/unbind 2>/dev/null || true
        sleep 0.5
    fi
    echo "$GPU" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
fi

sleep 1
echo ""
echo "[6] Running nvidia-smi:"
nvidia-smi
echo "========================================================"
