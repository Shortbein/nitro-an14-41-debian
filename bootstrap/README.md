# One-command Debian rebuild

This directory turns the validated Acer Nitro AN14-41 setup into a resumable,
idempotent Debian bootstrap.

## Target

- Acer Nitro AN14-41
- Debian 13 (trixie), KDE installation
- Ryzen 7 8845HS / Radeon 780M
- RTX 4060 Laptop GPU

The bootstrap configures the parts that were validated on the reference
machine: Debian Backports, AMD firmware/Mesa and i386 Vulkan, NVIDIA 595 open
kernel modules, PRIME-ready userspace, GameMode, ZRAM, Steam/Wine/Lutris,
MangoHud/Gamescope, GE-Proton, Heroic, ASense 0.3.0 with the AN14-41 RGB quirk,
80% battery limit, warm keyboard RGB, a Debian Backports fallback kernel and
XanMod x64v3 as the preferred kernel.

It also installs OpenClaw 2026.9.4 and the local Rudi policy, but provider OAuth
remains interactive by design.

## Fresh install

Install Debian 13 with KDE and create your normal desktop account. Then:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Shortbein/nitro-an14-41-debian.git
cd nitro-an14-41-debian
./bootstrap/install.sh
```

The script asks for sudo once, installs a root systemd resume service, and then
continues automatically. When the kernel stage is reached it reboots and
resumes by itself.

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

## What is intentionally not automated

Account authentication is never copied to Git. After the rebuild you still
need to sign in to Steam/Heroic and complete OpenClaw model-provider OAuth.
Steam may then download Proton Experimental automatically when selected.

For OpenClaw:

```bash
./bootstrap/post-openclaw-onboard.sh
# complete: ~/.openclaw/bin/openclaw onboard
./bootstrap/post-openclaw-onboard.sh --finish
```

No browser cookies, SSH/GPG keys, VPN credentials, password-store data,
OpenClaw tokens, API keys or `.env` secrets belong in this repository.

## Safety / failure behaviour

The runner only advances its stage after a stage succeeds. If DKMS cannot build
NVIDIA or ASense for XanMod, it stops **before rebooting**.

To stop the automation:

```bash
sudo systemctl disable --now nitro-bootstrap-resume.service
```

After fixing a failed stage:

```bash
sudo systemctl restart nitro-bootstrap-resume.service
```

To prevent automatic reboot during testing:

```bash
./bootstrap/install.sh --no-auto-reboot
```

## Capture the exact current machine

Before treating the repository as the canonical disaster-recovery source, run:

```bash
./scripts/capture-system.sh
git diff -- snapshot/current
git add snapshot/current
git commit -m "Capture sanitized current Debian configuration"
git push
```

The capture is deliberately sanitized. It records package/configuration state
without copying authentication or personal data.
