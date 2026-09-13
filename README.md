# Acer Nitro AN14-41 – Debian workstation and gaming setup

Configuration, compatibility fixes, diagnostics and benchmarks for an
Acer Nitro AN14-41 running Debian.

Hardware:

- AMD Ryzen 7 8845HS
- AMD Radeon 780M
- NVIDIA GeForce RTX 4060 Laptop GPU 8 GB
- 16 GB RAM
- 2560x1600 120 Hz display

Current baseline:

- Debian 13.7
- KDE Plasma / Wayland
- Kernel 6.12.107+deb13-amd64
- NVIDIA 595.91.07
- ASense 0.3.0

Repository areas:

- `asense/` – AN14-41 compatibility work
- `hardware-tests/` – hardware acceptance tests
- `benchmarks/` – reproducible performance tests
- `kernel-tests/` – kernel A/B comparisons
- `scripts/` – diagnostic and helper scripts

The Debian stock kernel remains the reference baseline before testing
alternative kernels.
