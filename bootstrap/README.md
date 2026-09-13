# One-command Debian rebuild

This directory turns the validated Acer Nitro AN14-41 setup into a resumable,
idempotent Debian bootstrap.

## Target

- Acer Nitro AN14-41
- Debian 13 (trixie), KDE installation
- Ryzen 7 8845HS / Radeon 780M
- RTX 4060 Laptop GPU

The bootstrap restores the captured workstation package/application set and the
parts that were explicitly validated on the reference machine: Debian
Backports, AMD firmware/Mesa and i386 Vulkan, NVIDIA 595 open kernel modules,
GameMode, zram-tools, Steam/Wine/Lutris, MangoHud/Gamescope, GE-Proton,
Proton-CachyOS, Heroic, the captured Flatpak applications, ASense 0.3.0 with the
AN14-41 RGB quirk, 80% battery limit, warm keyboard RGB, a Debian Backports
fallback kernel and XanMod x64v3 as the preferred kernel.

The captured manually-installed APT list is stored in `manifests/`. The runner
installs the portable part of that list and handles kernels, NVIDIA, ASense and
other order-sensitive components in dedicated stages.

## Fresh install

Install Debian 13 with KDE, network access and your normal desktop account.
Then:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Shortbein/nitro-an14-41-debian.git
cd nitro-an14-41-debian
./bootstrap/install.sh
```

The bootstrap persists its state, performs required reboots, and continues
automatically after boot through systemd.

Progress:

```bash
sudo journalctl -fu nitro-bootstrap-resume.service
```

State:

```bash
sudo cat /var/lib/nitro-bootstrap/stage
```

Final report:

```bash
sudo cat /var/lib/nitro-bootstrap/final-report.txt
```

## What gets restored

- all captured portable/manual APT packages that remain available
- Docker, VS Code, Google Chrome, AnyDesk and the official ChatGPT desktop app
- the five captured Flathub applications
- Steam/Wine/Lutris/Heroic and gaming utilities
- GE-Proton and the latest x86_64 Proton-CachyOS release
- GameMode scripts/config
- zram-tools (`zstd`, 50% RAM, priority 100)
- `acpi_backlight=native`
- AMD backports firmware/Mesa + i386 graphics stack
- NVIDIA 595 open DKMS branch
- ASense 0.3.0 + the AN14-41 RGB compatibility patch
- 80% battery limit and warm keyboard RGB
- Debian Backports kernel + XanMod x64v3
- Docker/SSH/AnyDesk/Bluetooth/fstrim services
- OpenClaw version/policy, without authentication

## Intentionally manual / not stored in Git

Account authentication is never copied to Git. After a rebuild you still need
to sign in to Steam/Heroic/Chrome/ChatGPT as applicable and complete OpenClaw
model-provider OAuth/onboarding. Secure Boot can also require an interactive
MOK enrollment.

The repository does not store game data, browser profiles/cookies, SSH/GPG
private keys, VPN credentials, password-manager data, NetworkManager Wi-Fi
profiles, API tokens, OpenClaw authentication, Docker registry credentials, or
arbitrary `$HOME` data.

Disk partitioning is also left to the Debian installer. The current machine has
a disk swap partition in addition to ZRAM, but the bootstrap will not create,
resize or destroy partitions automatically.

## Safety / failure behaviour

The runner advances its state only after a stage succeeds. If NVIDIA or ASense
DKMS cannot build for XanMod, the process stops before rebooting.

Stop the automation:

```bash
sudo systemctl disable --now nitro-bootstrap-resume.service
```

Retry after fixing a failed stage:

```bash
sudo systemctl restart nitro-bootstrap-resume.service
```

Disable automatic reboots while testing:

```bash
./bootstrap/install.sh --no-auto-reboot
```

## Capture a refreshed reference snapshot

```bash
./scripts/capture-system.sh
git diff -- snapshot/current
```

The collector sanitizes the snapshot and excludes credential-bearing areas.
Always review it before committing.


## VM test mode

For a disposable QEMU/KVM Debian 13 KDE VM:

```bash
git checkout feature/one-command-rebuild
git pull --ff-only
bash -n bootstrap/install.sh
bash -n bootstrap/runner.sh
./bootstrap/install.sh --test-mode
```

Test mode bypasses the Acer DMI check, validates the ASense download/checksum and
AN14-41 patch without performing Acer WMI/hardware writes, still builds the
NVIDIA DKMS module, installs XanMod, reboots, resumes automatically, and then
skips physical NVIDIA/ASense/RTD3 assertions that cannot succeed in QEMU.

Run the installer as the normal desktop user. It invokes sudo itself.
