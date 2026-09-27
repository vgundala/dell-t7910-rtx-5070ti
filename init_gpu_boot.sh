#!/usr/bin/env bash
# Automated Boot Script for RTX 5070 Ti in Slot 4
# Designed to run automatically at boot via systemd

BRIDGE="0000:00:03.0"
GPU="0000:04:00.0"

# Check if GPU is already initialized and working
if nvidia-smi >/dev/null 2>&1; then
    exit 0
fi

# 0. Trigger secondary bus reset to clear any stuck WPR2 state
if [ -f "/sys/bus/pci/devices/$BRIDGE/reset_subordinate" ]; then
    echo 1 > "/sys/bus/pci/devices/$BRIDGE/reset_subordinate" 2>/dev/null || true
    sleep 1
fi

# 1. Wake Root Port
echo on > "/sys/bus/pci/devices/$BRIDGE/power/control" 2>/dev/null || true
sleep 0.5

# 2. Check Link & Retrain if needed
WIDTH=$(cat "/sys/bus/pci/devices/$BRIDGE/current_link_width" 2>/dev/null || echo 0)
if [ "$WIDTH" = "0" ] || [ -z "$WIDTH" ]; then
    setpci -s 00:03.0 CAP_EXP+10.w=0020:0020 2>/dev/null || true
    sleep 1.5
fi

# 3. Rescan PCIe Bus if GPU not present
if [ ! -d "/sys/bus/pci/devices/$GPU" ]; then
    if [ -f "/sys/bus/pci/devices/$BRIDGE/rescan" ]; then
        echo 1 > "/sys/bus/pci/devices/$BRIDGE/rescan"
    fi
    echo 1 > /sys/bus/pci/rescan
    sleep 1.5
fi

# 4. Program bridge decoding windows
setpci -s 00:03.0 1c.b=10
setpci -s 00:03.0 1d.b=10
setpci -s 00:03.0 20.w=5000
setpci -s 00:03.0 22.w=5400
setpci -s 00:03.0 24.w=0bf1
setpci -s 00:03.0 26.w=2ff1
setpci -s 00:03.0 28.l=00000301
setpci -s 00:03.0 2c.l=00000301
setpci -s 00:03.0 04.w=0407:0407

# 5. Enable GPU Bus Mastering and Memory
if [ -d "/sys/bus/pci/devices/$GPU" ]; then
    setpci -s 04:00.0 04.w=0007:0007 2>/dev/null || true
fi

# 6. Load Modules & Bind Driver
modprobe nvidia 2>/dev/null || true
modprobe nvidia_uvm 2>/dev/null || true
modprobe nvidia_modeset 2>/dev/null || true
modprobe nvidia_drm 2>/dev/null || true

if [ -d "/sys/bus/pci/devices/$GPU/driver" ]; then
    if ! nvidia-smi >/dev/null 2>&1; then
        echo "$GPU" > "/sys/bus/pci/devices/$GPU/driver/unbind" 2>/dev/null || true
        sleep 0.5
        echo "$GPU" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
    fi
elif [ -d /sys/bus/pci/drivers/nvidia ]; then
    echo "$GPU" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
fi

sleep 1
nvidia-smi >/dev/null 2>&1 || true
exit 0
