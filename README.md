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

## Adding packages

Create a directory with a `PKGBUILD`:

```
vero-on-arch/
├── my-package/
│   ├── PKGBUILD
│   └── .nvchecker.toml  # optional: upstream version tracking
```

Pushes to `main` trigger the build workflow, compile new packages, update the database, and publish release assets to the `x86_64` tag.
