# Title:
PSA & Guide: Running RTX 5070 Ti (Blackwell) on Dell Precision / Legacy Workstations (Slot 4 Seating Trap, Bridge Windows, IOMMU Fixes)

If you are dropping an RTX 50-series card (Blackwell, e.g., RTX 5070 Ti 16GB) into a Dell Precision Tower (T7910, T7810, T7920) or similar legacy Haswell/Broadwell-EP dual Xeon workstations, you will likely hit a wall where `nvidia-smi` reports `No devices were found` or the driver crashes with `rm_init_adapter failed, returning -1`.

I spent hours untangling this down to the register and physical pin level. Here is the complete breakdown and the fix.

---

### 1. The Physical Seating Trap: Pin B81 and the Motherboard Harness

On the Dell Precision T7910, the thick 24-pin motherboard power wiring harness runs directly beneath PCIe Slot 4 (the CPU 1 primary x16 slot). The rigid cable bundle pushes upward against the GPU cooler shroud.

This produces a false positive:
* Auxiliary PCIe power cables supply 12V directly from the PSU.
* GPU fans spin and RGB lights power on.
* The system looks powered and seated.

Mechanically, the cable pressure lifts the rear edge of the card out of the PCIe socket. This disconnects **Pin B81 (PRSNT2#)**, the short presence-detect pin at the far right edge of the x16 slot.

Query the root port with `setpci`:

```bash
setpci -s 00:03.0 0x148.w
```

If it returns `0000`, the motherboard reads the slot as empty. Link width drops to 0.

**Warning on SFF / Short GPUs:** Do not buy or install Small Form Factor (SFF) or short-bracket cards in Slot 4. SFF cards lack the structural rigidity and clearance needed to counteract the power harness pressure. The card will bow and lift. Use a card with a rigid full-length metal backplate and dual-slot profile.

*Note on other workstations:* This specific harness conflict is unique to Dell Precision layouts. HP Z-series (Z840/Z8) and Lenovo ThinkStations (P900/P910/P920) use separate cable runs and will not have this exact physical obstruction in their primary x16 slots.

---

### 2. The BIOS POST Timeout & Closed Bridge Windows

Dell BIOS A34 completes its PCIe bus probe during the initial 1-2 seconds of POST. Because the Blackwell GPU initializes slowly or was unseated during power-on, the BIOS disables the root port bridge (`00:03.0`).

The bridge registers are left closed:
* Memory Base `0x20.w = fff0`
* Memory Limit `0x22.w = 000f`

Base exceeds Limit, disabling MMIO forwarding. When Linux boots and rescans the PCIe bus, the GPU appears in `lspci`, but any read to BAR0 aborts with `[Errno 5] Input/output error` (returning `0xFFFFFFFF`). The NVIDIA driver fails with:

```text
NVRM: GPU 0000:04:00.0: rm_init_adapter failed, returning -1
```

To fix this, program the bridge registers manually:

```bash
# Enable I/O decoding
setpci -s 00:03.0 1c.b=10
setpci -s 00:03.0 1d.b=10

# Non-prefetchable MMIO window (0x50000000 - 0x540fffff)
setpci -s 00:03.0 20.w=5000
setpci -s 00:03.0 22.w=5400

# Prefetchable MMIO window (0x3010bf00000 - 0x3012fffffff)
setpci -s 00:03.0 24.w=0bf1
setpci -s 00:03.0 26.w=2ff1
setpci -s 00:03.0 28.l=00000301
setpci -s 00:03.0 2c.l=00000301

# Command register: Bus Master, Memory Space, I/O Space
setpci -s 00:03.0 04.w=0407:0407
```

*Watch the byte order:* Register `0x24` requires `0bf1`. Writing `bf01` reverses the nibbles, making Base > Limit and breaking MMIO reads.

---

### 3. Intel IOMMU / DMAR Storm with Blackwell GSP

Blackwell relies on the on-die GPU System Processor (GSP) firmware bootloader. During initialization, the GSP issues DMA requests to physical address `0xfff01000`.

Default Linux Intel VT-d remapping blocks these requests, logging over 290,000 DMAR read faults in `dmesg`:

```text
DMAR: [DMA Read NO_PASID] Request device [04:00.0] fault addr 0xfff01000 [fault reason 0x05] PTE Read access is not set
```

Fix this permanently by setting kernel boot parameters:

```bash
# Pop!_OS (systemd-boot)
sudo kernelstub -a "pci=realloc iommu=pt"

# GRUB (Ubuntu / Debian)
# Append to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub:
# GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pci=realloc iommu=pt"
sudo update-grub
```

---

### 4. GSP WPR2 Reset Lockout

If the driver fails initialization partway through, Write-Protected Region 2 (WPR2) remains locked in VRAM (`unexpected WPR2 already up`).

Issue a Secondary Bus Reset on the root port to clear it:

```bash
echo 1 > /sys/bus/pci/devices/0000:00:03.0/reset_subordinate
```

---

### 5. Automated Boot & Hardware Seating Services

To make this hands-off, I created two systemd services:

1. **Boot Initialization Service (`init-5070ti.service`):** Runs `/usr/local/bin/init_gpu_boot.sh` at boot before the display manager loads. It triggers a secondary bus reset, retrains the link, rescans the bus, programs the bridge registers, and binds the `nvidia` driver.
2. **Real-time Seating Monitor (`gpu-presence-monitor.service`):** Runs `/usr/local/bin/gpu_presence_monitor.py`. It polls register `0x148` every 2 seconds. If cable tension levers the card up and disconnects Pin B81, it posts a single persistent desktop notification so you know immediately. When pushed back down, it auto-dismisses the alert and triggers initialization without notification spam.

The full scripts, systemd units, and installer are available in the repository.

Once configured, the RTX 5070 Ti operates stably at idle (P8 state, 35°C, 21W) and delivers full CUDA 13.0 performance under heavy compute loads.
