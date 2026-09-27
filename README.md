# NVIDIA RTX 5070 Ti (Blackwell) on Dell Precision T7910 & Legacy Workstations

Hardware fixes, register programming, and automated services for running RTX 50-series (Blackwell) GPUs on older enterprise workstations (Dell Precision T7910, T7810, T7920).

## The Problems Solved

1. **Physical Pin B81 Clearance Trap:** The motherboard power harness under Slot 4 acts as a lever against the GPU cooler shroud, lifting the rear pins (Pin B81 / `PRSNT2#`). Aux power gives false positive LED/fan activity while the slot registers empty (`0x0000`).
2. **Card Thickness & Slot 4 Clearance:** Oversized 2.5-slot and 3-slot cards press hard against the motherboard power harness directly beneath Slot 4, creating severe seating pressure. Slimmer 2-slot or compact/SFF cards are preferable in Slot 4 to avoid harness collision.
3. **BIOS POST Disablement & Closed Bridge Windows:** Dell BIOS A34 disables root port `00:03.0` decoding windows (`Base > Limit`) during early POST, causing `[Errno 5] Input/output error` and `rm_init_adapter failed (-1)`.
4. **Blackwell GSP DMA / IOMMU Faults:** Strict Intel VT-d blocks GSP DMA at `0xfff01000`, causing 290,000+ DMAR read faults.
5. **GSP WPR2 Lockout:** Incomplete initialization locks Write-Protected Region 2 until secondary bus reset.

---

## Quick Start (Automated Installer)

Run the installer to copy scripts to `/usr/local/bin` and enable both boot and real-time monitoring services:

```bash
sudo ./install_service.sh
```

Ensure bootloader parameters are set for IOMMU pass-through:

```bash
# Pop!_OS (systemd-boot)
sudo kernelstub -a "pci=realloc iommu=pt"

# Debian / Ubuntu (GRUB)
# Add "pci=realloc iommu=pt" to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub
sudo update-grub
```

---

## Using with AI Coding Tools

Point your AI coding assistant (Claude Code, Antigravity, Cursor, Aider) to this repository to inspect and configure your machine:

```bash
git clone https://github.com/vgundala/dell-t7910-rtx-5070ti.git
cd dell-t7910-rtx-5070ti
```

Prompt your agent:
> "Inspect my PCIe slot status and bridge decoding windows using this repository's diagnostic scripts, then run the installer to enable the boot and monitoring services."

The repository includes [`AGENTS.md`](AGENTS.md) and [`llms.txt`](llms.txt) with pre-configured register maps, verification commands, and hardware constraints for automated agents.

---

## File Manifest

| File | Description |
| :--- | :--- |
| [`RTX_5070Ti_DELL_T7910_GUIDE.md`](RTX_5070Ti_DELL_T7910_GUIDE.md) | Full technical breakdown and manual step-by-step resolution |
| [`AGENTS.md`](AGENTS.md) | Execution guide and constraints for AI coding tools (Claude Code, Cursor, Aider) |
| [`llms.txt`](llms.txt) | Compact summary for LLM search engines and web crawlers |
| [`init_gpu_boot.sh`](init_gpu_boot.sh) | Boot script: resets secondary bus, retrains link, rescans bus, programs bridge, binds driver |
| [`init-5070ti.service`](init-5070ti.service) | Systemd oneshot boot service |
| [`gpu_presence_monitor.py`](gpu_presence_monitor.py) | Hardware daemon polling register `0x148` for Pin B81 contact, sends persistent desktop alert on lift |
| [`gpu-presence-monitor.service`](gpu-presence-monitor.service) | Systemd user-session monitoring daemon |
| [`install_service.sh`](install_service.sh) | Root installer script |
| [`troubleshooting.md`](troubleshooting.md) | Diagnostic log notes and raw hardware register values |
| [`index.html`](index.html) | Standalone dark-mode web page version |

---

## Bridge Register Reference (`0000:00:03.0`)

```bash
setpci -s 00:03.0 1c.b=10
setpci -s 00:03.0 1d.b=10
setpci -s 00:03.0 20.w=5000
setpci -s 00:03.0 22.w=5400
setpci -s 00:03.0 24.w=0bf1
setpci -s 00:03.0 26.w=2ff1
setpci -s 00:03.0 28.l=00000301
setpci -s 00:03.0 2c.l=00000301
setpci -s 00:03.0 04.w=0407:0407
```

*Note on byte order:* Offset `0x24` requires `0bf1`. Writing `bf01` causes Base > Limit and causes immediate MMIO bus errors.
