# Title:
Running RTX 5070 Ti (Blackwell) on Dell Precision T7910 / Legacy Workstations: Slot 4 Pin Seating, Bridge Windows, and IOMMU Faults

**Tags:** `hardware`, `linux`, `nvidia`, `homelab`, `dell`

Dropping an NVIDIA RTX 50-series card (Blackwell architecture, e.g., RTX 5070 Ti 16GB) into older dual-socket enterprise workstations like the Dell Precision Tower 7910 (dual Xeon E5-2640 v4, C612 chipset) uncovers several distinct integration failures across mechanical clearance, BIOS POST handshakes, PCIe bridge registers, and VT-d IOMMU tables.

If your card fans spin and RGB lights up, but `nvidia-smi` reports `No devices were found` or dmesg logs `rm_init_adapter failed, returning -1`, work through these steps.

---

## 1. Mechanical Seating Failure: The Slot 4 Power Harness & Pin B81

The Dell Precision T7910, T7810, and T7920 route the thick 24-pin motherboard main power cable directly underneath PCIe Slot 4 (the CPU 1 primary x16 slot). This rigid bundle presses hard against the GPU cooler shroud.

This causes a deceptive failure mode:
1. Auxiliary PCIe 12V cables deliver power directly from the PSU. Fans spin and RGB lighting turns on.
2. The card looks seated at first glance.
3. The cable harness acts as a lever against the cooler shroud, tilting the rear edge of the PCB out of the slot.
4. Pin B81 (`PRSNT2#`), the short presence-detect pin at the far right of the PCIe x16 slot, loses electrical contact.

Check the slot status register on root port `0000:00:03.0`:

```bash
setpci -s 00:03.0 0x148.w
```

A return value of `0000` indicates the motherboard considers the slot physically empty, locking link width to 0. When properly seated and latched, this register returns `0048` or `0148`.

> **Warning on SFF / Short-PCB GPUs:** Do not install Small Form Factor (SFF) or short-bracket GPUs in Slot 4 on Dell Precision chassis. SFF cards lack the structural rigidity and clearance needed to overcome harness pressure. The card will flex and disconnect pins. Use a card with a rigid full-length metal backplate, or route the card to an alternative slot.
>
> *Note on workstation vendors:* This physical interference is specific to Dell Precision chassis. HP Z-series (Z840, Z8 G4) and Lenovo ThinkStation (P900, P910, P920) use separate cable channels and do not obstruct the primary x16 slot.

---

## 2. Dell BIOS POST Timeout & Closed Bridge Windows

Dell BIOS A34 checks PCIe slots during the first 1-2 seconds of POST. If the card was levered or delayed in its handshake, the BIOS leaves root port bridge `0000:00:03.0` decoding windows closed.

The disabled registers report:
* Memory Base `0x20.w = fff0`
* Memory Limit `0x22.w = 000f`

Base exceeds Limit. Downstream MMIO decoding is disabled. When Linux triggers a bus rescan (`echo 1 > /sys/bus/pci/rescan`), the GPU appears in `lspci`, but reading BAR0 (`/sys/bus/pci/devices/0000:04:00.0/resource0`) aborts with `[Errno 5] Input/output error`, returning `0xFFFFFFFF`. The NVIDIA driver fails with `rm_init_adapter failed, returning -1`.

Reprogram the bridge decoding registers via `setpci`:

```bash
# Enable I/O decoding
setpci -s 00:03.0 1c.b=10
setpci -s 00:03.0 1d.b=10

# Memory window (0x50000000 - 0x540fffff)
setpci -s 00:03.0 20.w=5000
setpci -s 00:03.0 22.w=5400

# Prefetchable window (0x3010bf00000 - 0x3012fffffff)
setpci -s 00:03.0 24.w=0bf1
setpci -s 00:03.0 26.w=2ff1
setpci -s 00:03.0 28.l=00000301
setpci -s 00:03.0 2c.l=00000301

# Bus Master, Memory Space, I/O Space, SERR
setpci -s 00:03.0 04.w=0407:0407
```

**Byte order note:** Register `0x24` requires `0bf1`. Writing `bf01` causes Base > Limit and causes immediate MMIO bus errors.

---

## 3. Intel VT-d / IOMMU DMAR Storm

Blackwell cards use an on-die GPU System Processor (GSP) that initiates DMA transfers to physical host memory at `0xfff01000`.

Default Linux Intel IOMMU remapping rejects these DMA packets, flooding `dmesg` with over 290,000 faults:

```text
DMAR: [DMA Read NO_PASID] Request device [04:00.0] fault addr 0xfff01000 [fault reason 0x05] PTE Read access is not set
```

Enable pass-through mode in the kernel command line:

```bash
# Pop!_OS (systemd-boot)
sudo kernelstub -a "pci=realloc iommu=pt"

# Debian / Ubuntu (GRUB)
# Add "pci=realloc iommu=pt" to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub
sudo update-grub
```

---

## 4. Resetting Locked WPR2 Firmware State

If GSP initialization fails partway through, Write-Protected Region 2 (WPR2) remains locked in GPU memory (`unexpected WPR2 already up`).

Issue a Secondary Bus Reset on root port `00:03.0` to clear it:

```bash
echo 1 > /sys/bus/pci/devices/0000:00:03.0/reset_subordinate
```

---

## 5. Automated Services & Seating Monitor

[details="Boot Initialization Script (init_gpu_boot.sh)"]
```bash
#!/bin/bash
ROOT_PORT="0000:00:03.0"
GPU_ADDR="0000:04:00.0"

echo 1 > /sys/bus/pci/devices/${ROOT_PORT}/reset_subordinate
sleep 1
setpci -s ${ROOT_PORT} 0x50.w=0x0020
sleep 2
echo 1 > /sys/bus/pci/devices/${ROOT_PORT}/rescan
sleep 1
setpci -s ${ROOT_PORT} 1c.b=10 1d.b=10 20.w=5000 22.w=5400 24.w=0bf1 26.w=2ff1 28.l=00000301 2c.l=00000301 04.w=0407:0407
echo ${GPU_ADDR} > /sys/bus/pci/drivers/nvidia/bind
```
[/details]

[details="Hardware Presence Monitor Daemon (gpu_presence_monitor.py)"]
```python
#!/usr/bin/env python3
import subprocess
import time
import os

ROOT_PORT = "00:03.0"
ALERT_ACTIVE = False

def check_presence():
    try:
        output = subprocess.check_output(
            ["setpci", "-s", ROOT_PORT, "0x148.w"], text=True
        ).strip()
        return output != "0000"
    except subprocess.CalledProcessError:
        return False

def send_alert(message, clear=False):
    timeout = 2000 if clear else 0
    os.system(f"notify-send -t {timeout} 'GPU Status' '{message}'")

while True:
    seated = check_presence()
    if not seated and not ALERT_ACTIVE:
        send_alert("GPU unseated from Slot 4. Check physical clearance.", clear=False)
        ALERT_ACTIVE = True
    elif seated and ALERT_ACTIVE:
        send_alert("GPU reseated successfully.", clear=True)
        ALERT_ACTIVE = False
    time.sleep(2)
```
[/details]

The daemon monitors register `0x148` every 2 seconds. If cable tension lifts the card and disconnects Pin B81, it generates a single persistent desktop alert. Reseating the card auto-dismisses the notification and restores initialization without alert spam.
