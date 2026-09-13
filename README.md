# Acer Nitro AN14-41 – Debian workstation and gaming setup

Reproducible configuration, compatibility fixes, diagnostics and benchmarks
for an Acer Nitro AN14-41 running Debian.

Hardware:

- AMD Ryzen 7 8845HS
- AMD Radeon 780M
- NVIDIA GeForce RTX 4060 Laptop GPU 8 GB
- 16 GB RAM
- 2560x1600 120 Hz display

Validated target state (2026-09-13):

- Debian 13.7 / KDE Plasma / Wayland
- XanMod 7.2.5 x64v3 as primary kernel
- Debian Backports 7.1.8 as fallback kernel
- NVIDIA 595.91.07 open kernel module
- Mesa 26.1.2 from Backports
- AMD desktop + NVIDIA PRIME render offload
- NVIDIA RTD3 validated
- GameMode + ZRAM + Gamescope + MangoHud
- ASense 0.3.0 with AN14-41 RGB compatibility patch

## Disaster-recovery bootstrap

A fresh Debian 13 KDE install can be rebuilt from this repository:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/Shortbein/nitro-an14-41-debian.git
cd nitro-an14-41-debian
./bootstrap/install.sh
```

The bootstrap persists its state, performs required reboots, and automatically
continues after boot. See [`bootstrap/README.md`](bootstrap/README.md).

To save a sanitized snapshot of the exact current system before a reinstall:

```bash
./scripts/capture-system.sh
```

Repository areas:

- `bootstrap/` – one-command rebuild and reboot-resume state machine
- `snapshot/` – sanitized current-system inventory (generated locally)
- `asense/` – AN14-41 compatibility work
- `gamemode/` – validated GameMode power profile configuration
- `hardware-tests/` – hardware acceptance tests
- `benchmarks/` – reproducible performance tests
- `kernel-tests/` – kernel A/B comparisons
- `scripts/` – audit/export/helper scripts
- `openclaw/` – non-secret agent policy only

Secrets and personal data are intentionally excluded from Git.
