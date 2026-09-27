# AGENTS.md

Instructions for AI coding agents (Claude Code, Antigravity, Cursor, Aider) operating in this repository.

## Hardware Architecture & Target Mapping

* **Chassis:** Dell Precision Tower 7910 (dual Intel Xeon E5-2600 v4 series, C612 chipset).
* **Target Slot:** PCIe Slot 4 (CPU 1, Root Port `0000:00:03.0`).
* **GPU Endpoint:** `0000:04:00.0` (NVIDIA RTX 50-series / Blackwell architecture).
* **Motherboard Power Harness:** Runs directly beneath Slot 4. Causes physical levering against thick 2.5-slot and 3-slot cooler shrouds, disconnecting Pin B81 (`PRSNT2#`).

## Diagnostic Commands

Run these scripts to inspect system state:

```bash
# Check root port presence detect, power state, and link width
sudo ./check_slot4.sh

# Check if NVIDIA GPU responded on bus and driver status
./check_gpu.sh

# Force PCIe link retrain and bus rescan
sudo ./force_retrain.sh

# Clean hardware reset and bridge programming
sudo ./reset_and_init.sh
```

## Hardware Register Reference (`0000:00:03.0`)

* **I/O Decoding:** `1c.b=10 1d.b=10`
* **Non-prefetchable MMIO:** Base `20.w=5000` (0x50000000), Limit `22.w=5400` (0x540fffff)
* **Prefetchable MMIO:** Base `24.w=0bf1` (0x3010bf00000), Limit `26.w=2ff1` (0x3012fffffff)
* **Upper 32-bit Prefetchable:** `28.l=00000301 2c.l=00000301`
* **Command Register:** `04.w=0407:0407` (Bus Master, Memory Space, I/O Space)

**Endianness Warning:** Register `0x24` requires `0bf1`. Never write `bf01`—it inverts nibbles and causes immediate MMIO bus faults.

## Installation & Verification Criteria

1. To install systemd boot and monitoring daemons:
   ```bash
   sudo ./install_service.sh
   ```
2. Verify services:
   ```bash
   systemctl status init-5070ti.service
   systemctl status gpu-presence-monitor.service
   ```
3. Verification of success:
   `nvidia-smi` returns zero errors and displays the GPU in P8 state.
