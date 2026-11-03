# vero-on-arch

Custom Arch Linux package repository built automatically via GitHub Actions and hosted on GitHub Releases.

## Usage

Add the following to `/etc/pacman.conf`:

```ini
[vero-on-arch]
SigLevel = Optional TrustAll
Server = https://github.com/veronoicc/vero-on-arch/releases/download/$arch
```

Synchronize repositories:

```bash
sudo pacman -Sy
```

## Packages

| Package | Description |
|---|---|
| `cordial-bin` | Roblox's official Android build natively on Linux |
| `equibop-vero-git` | Custom Discord desktop app with Equicord git and userplugins |
| `linux-cachyos-surface` | CachyOS Linux kernel with Microsoft Surface patches |
| `oh-my-pi-gui` | Desktop GUI for the omp coding agent (source build) |
| `oh-my-pi-gui-bin` | Desktop GUI for the omp coding agent (official prebuilt release) |
| `surface-pro8-camera-dkms-git` | DKMS driver for Surface Pro 8 cameras |
| `surface-pro8-cameras-git` | Userland bridge and systemd services for Surface Pro 8 cameras |
| `vd55g-firmware-git` | Camera sensor firmware for Surface Pro 8 |

## Adding packages

Create a directory with a `PKGBUILD`:

```
vero-on-arch/
├── my-package/
│   ├── PKGBUILD
│   └── .nvchecker.toml  # optional: upstream version tracking
```

Pushes to `main` trigger the build workflow, compile new packages, update the database, and publish release assets to the `x86_64` tag.
