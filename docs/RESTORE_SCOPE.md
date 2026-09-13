# Restore scope

The repository rebuilds the **operating-system/workstation configuration**. It
is not a backup of personal data or application accounts.

## Automatically restored

- Debian 13 repository components and Backports
- captured portable/manual APT application set
- Docker, Visual Studio Code, Google Chrome, AnyDesk and ChatGPT Desktop repos/apps
- AMD microcode and firmware
- Mesa/RADV amd64+i386
- NVIDIA 595 branch using open kernel modules
- Steam, Wine, Lutris and Heroic
- MangoHud, Gamescope and GameMode
- GE-Proton + Proton-CachyOS
- captured Flathub application set
- zram-tools: zstd, 50% RAM, priority 100
- `acpi_backlight=native`
- ASense 0.3.0 + AN14-41 RGB compatibility patch
- keyboard RGB `STATIC #FFB000 @ 30%`
- ASense battery limit 80%
- Debian Backports kernel as fallback
- XanMod x64v3 as preferred kernel
- DKMS validation before reboot
- automatic resume after reboot
- OpenClaw CLI 2026.9.4 and safe local policy

## Reference-only manifests

The repository retains sanitized reference manifests for the manually installed
APT package set, APT repositories/preferences, enabled system/user units,
DKMS state, display setup, swap/ZRAM state and Steam compatibility tools.
Exact versions that matter to the validated restore target are recorded in
`bootstrap/versions.env`.

The complete transitive dpkg dependency/version database is intentionally not
pinned. Freezing every Debian dependency version would make future reinstalls
less reliable and less secure.

## Manual by design

- Debian installer partitioning and user password
- disk swap partition sizing
- Secure Boot MOK enrollment when required
- Steam/Heroic/Chrome/ChatGPT account sign-in
- Proton Experimental selection/download in Steam
- OpenClaw provider OAuth/onboarding
- VPN/corporate credentials
- private SSH/GPG keys and credential stores
- game installations and copyrighted game data

## Explicitly excluded from Git

- passwords, tokens and API keys
- browser cookies/profiles/password stores
- OpenClaw authentication state
- NetworkManager connection profiles and Wi-Fi PSKs
- SSH/GPG private keys
- VPN profiles containing credentials
- `.env` secrets
- Docker registry credentials
- arbitrary home-directory content

The bootstrap is a reproducible configuration system, not a disk image.
