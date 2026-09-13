# Restore scope

The repository is intended to rebuild the **system configuration**, not clone
personal data or credentials.

## Automated

- Debian 13 repository components and Backports
- AMD microcode and firmware
- Mesa/RADV amd64+i386
- NVIDIA 595 branch using open kernel modules
- Steam, Wine, Lutris, Heroic
- MangoHud, Gamescope, GameMode
- GE-Proton 11-6
- ZRAM (zstd, 50% RAM, priority 100)
- `acpi_backlight=native`
- ASense 0.3.0 + AN14-41 RGB compatibility patch
- keyboard RGB `STATIC #FFB000 @ 30%`
- ASense battery limit 80%
- Debian Backports kernel as fallback
- XanMod x64v3 as the newest/preferred kernel
- DKMS validation before reboot
- OpenClaw CLI 2026.9.4 and safe local policy
- automatic resume after reboot

## Manual by design

- Debian installer partitioning and user password
- Secure Boot MOK enrollment if Secure Boot is enabled and firmware requires it
- Steam/Heroic account login
- Proton Experimental selection/download in Steam
- OpenClaw provider OAuth/onboarding
- VPN, corporate credentials and private keys
- game installations and copyrighted game data

## Not restored blindly

Arbitrary files from `$HOME`, browser profiles, password managers, SSH/GPG
material, `.env` files, cookies and application tokens are excluded. These are
not safe Git configuration material.
