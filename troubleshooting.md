# RTX 5070 Ti Installation & Permanent Solution Guide

**System:** Dell Precision Tower 7910  
**GPU:** ZOTAC NVIDIA GeForce RTX 5070 Ti (`10de:2c05`, rev a1)  
**Slot Target:** Physical Slot 4 (CPU 1, Root Port `0000:00:03.0`, Bus 04)  
**Status:** **FULLY OPERATIONAL & INITIALIZED!**  
**Idle Specs:** 35°C, 21W idle, 0% fan, 16 GB VRAM, CUDA 13.0, Driver 580.173.02  

---

## 1. Summary of What Was Solved

1. **Physical Obstruction (The Root Hardware Issue):**
   - The Dell motherboard power cable harness was pressing upward against the bottom of the GPU cooler.
   - This slight upward pressure tilted the heavy triple-slot card, lifting **Pin B81 (PRSNT)** at the far end of the PCIe slot out of contact.
   - Firmly reseating the card and relieving cable tension restored physical electrical contact (`Presence Detect: 1` / `0x0148`, `width: 8`).

2. **Dell T7910 Firmware Limitations:**
   - The Dell Precision T7910 BIOS (A34 from 2020) does not natively size or open 64-bit MMIO apertures for high-end modern GPUs in secondary slots during POST, leaving bridge `00:03.0` memory registers disabled (`Base > Limit`).
   - The Intel IOMMU (VT-d) in default mode blocked the GPU's GSP processor firmware DMA loads.

3. **Kernel Parameters Configured (Permanent via `kernelstub`):**
   - `pci=realloc`: Instructs Linux to dynamically allocate PCI address space.
   - `iommu=pt`: Enables 1:1 direct DMA pass-through, completely eliminating all DMAR IOMMU faults.

---

## 2. Permanent Automated Services

We have set up two background services to handle boot initialization and real-time seating monitoring:

### Service 1: `init-5070ti.service` (Boot Initialization)
* **Script:** [`init_gpu_boot.sh`](init_gpu_boot.sh)
* **Role:** Runs on boot before the login screen. Automatically programs the motherboard bridge registers and binds the driver in ~1 second if the BIOS left them disabled.

### Service 2: `gpu-presence-monitor.service` (Real-Time Seating Monitor)
* **Script:** [`gpu_presence_monitor.py`](gpu_presence_monitor.py)
* **Role:** Continuously polls the PCIe hardware presence detect pin (Pin B81 / `PRSNT`):
  * **If card end pins lift / lose contact:** Displays a single **persistent critical desktop notification** that remains visible until fixed or dismissed. It will **not** spam repeated notifications.
  * **When contact is restored:** Automatically closes the warning notification, sends a brief confirmation alert, and automatically triggers initialization if needed.

---

## 3. Installation Command

To install and activate both services permanently:

```bash
sudo ./install_service.sh
```
