#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="vero-on-arch"
ARCH="x86_64"
DIST_DIR="$REPO_ROOT/dist"

mkdir -p "$DIST_DIR"
cd "$DIST_DIR"

echo "=== Fetching existing repository database ==="
if command -v gh >/dev/null 2>&1; then
    gh release download "$ARCH" --pattern "${REPO_NAME}.*" --dir "$DIST_DIR" 2>/dev/null || echo "No existing database found on GitHub Releases."
fi

REPO_DB="$DIST_DIR/${REPO_NAME}.db.tar.gz"
BUILT_PKGS=()
KNOWN_PKGS=()
DB_MODIFIED=0

echo "=== Scanning for packages ==="
for pkgdir in "$REPO_ROOT"/*/; do
    [ -d "$pkgdir" ] || continue
    [ -f "${pkgdir}PKGBUILD" ] || continue

    pkgname_dir="$(basename "$pkgdir")"
    if [ "$pkgname_dir" = "dist" ] || [ "$pkgname_dir" = "scripts" ]; then
        continue
    fi

    echo "--- Processing: $pkgname_dir ---"
    cd "$pkgdir"

    pkgname=""
    pkgver=""
    pkgrel=""
    if pkgfile="$(basename "$(makepkg --packagelist 2>/dev/null | head -n1)" 2>/dev/null)" && [ -n "$pkgfile" ]; then
        if [[ "$pkgfile" =~ ^(.+)-([^-]+)-([^-]+)-([^-]+)\.pkg\.tar\.(zst|xz|gz)$ ]]; then
            pkgname="${BASH_REMATCH[1]}"
            pkgver="${BASH_REMATCH[2]}"
            pkgrel="${BASH_REMATCH[3]}"
        fi
    fi

    if [ -z "$pkgname" ] || [ -z "$pkgver" ] || [ -z "$pkgrel" ]; then
        read -r pkgname pkgver pkgrel < <(bash -c 'source ./PKGBUILD 2>/dev/null; echo "${pkgname:-} ${pkgver:-} ${pkgrel:-}"' || true)
    fi

    echo "Package: $pkgname, Version: $pkgver-$pkgrel"
    KNOWN_PKGS+=("$pkgname")
    # Check if this version already exists in repo database
    if [ -f "$REPO_DB" ] && tar -ztf "$REPO_DB" 2>/dev/null | grep -qx "${pkgname}-${pkgver}-${pkgrel}/"; then
        echo "Package $pkgname $pkgver-$pkgrel is already in repository database. Skipping build."
        continue
    fi

    echo "Building $pkgname..."
    rm -f *.pkg.tar.zst src pkg -rf

    BUILD_SUCCESS=0
    if command -v paru >/dev/null 2>&1; then
        echo "Attempting build with paru..."
        if paru -B . --noconfirm --chroot 2>/dev/null; then
            BUILD_SUCCESS=1
        elif paru -B . --noconfirm 2>/dev/null; then
            BUILD_SUCCESS=1
        fi
    fi

    if [ "$BUILD_SUCCESS" -ne 1 ] && command -v yay >/dev/null 2>&1; then
        echo "Attempting build with yay..."
        if yay -B . --noconfirm 2>/dev/null; then
            BUILD_SUCCESS=1
        fi
    fi

    if [ "$BUILD_SUCCESS" -ne 1 ] && command -v makepkg >/dev/null 2>&1; then
        echo "Attempting build with makepkg..."
        if makepkg -s --noconfirm; then
            BUILD_SUCCESS=1
        fi
    fi
    if [ "$BUILD_SUCCESS" -ne 1 ]; then
        echo "Failed to build $pkgname" >&2
        exit 1
    fi

    # Lint package with namcap
    if command -v namcap >/dev/null 2>&1; then
        echo "Linting PKGBUILD with namcap:"
        namcap PKGBUILD || true
        for p in *.pkg.tar.zst; do
            if [ -f "$p" ]; then
                echo "Linting $p with namcap:"
                namcap "$p" || true
            fi
        done
    fi

    # Move built package files to DIST_DIR
    for p in *.pkg.tar.zst; do
        if [ -f "$p" ]; then
            cp -f "$p" "$DIST_DIR/"
            BUILT_PKGS+=("$DIST_DIR/$(basename "$p")")
            rm -f "$p"
        fi
    done

    rm -rf src/ pkg/
    cd "$REPO_ROOT"
done

cd "$DIST_DIR"

# Prune packages from DB that were deleted from repo
if [ -f "$REPO_DB" ]; then
    mapfile -t DB_PKGS < <(tar -ztf "$REPO_DB" 2>/dev/null | grep '/$' | sed -E 's@/.*@@' | sed -E 's@-[^-]+-[^-]+$@@' | sort -u || true)
    for db_pkg in "${DB_PKGS[@]}"; do
        [ -n "$db_pkg" ] || continue
        is_known=0
        for known in "${KNOWN_PKGS[@]}"; do
            if [ "$db_pkg" = "$known" ]; then
                is_known=1
                break
            fi
        done

        if [ "$is_known" -eq 0 ]; then
            echo "Package '$db_pkg' removed from repo. Pruning from database..."
            repo-remove "${REPO_NAME}.db.tar.gz" "$db_pkg" || true
            DB_MODIFIED=1

            if [ "${1:-}" = "--publish" ] && command -v gh >/dev/null 2>&1; then
                gh release view "$ARCH" --json assets --jq ".assets[].name" 2>/dev/null | grep -E "^${db_pkg}-[0-9]" | while read -r asset; do
                    echo "Deleting asset '$asset' from GitHub release..."
                    gh release delete-asset "$ARCH" "$asset" -y || true
                done
            fi
        fi
    done

    if [ "$DB_MODIFIED" -eq 1 ]; then
        cp -f --remove-destination "${REPO_NAME}.db.tar.gz" "${REPO_NAME}.db"
        cp -f --remove-destination "${REPO_NAME}.files.tar.gz" "${REPO_NAME}.files"
    fi
fi

if [ ${#BUILT_PKGS[@]} -eq 0 ]; then
    echo "No new packages to add."
else
    echo "=== Updating repository database ==="
    repo-add "${REPO_NAME}.db.tar.gz" "${BUILT_PKGS[@]}"

    # Replace symlinks with real files for GitHub Releases compatibility
    cp -f --remove-destination "${REPO_NAME}.db.tar.gz" "${REPO_NAME}.db"
    cp -f --remove-destination "${REPO_NAME}.files.tar.gz" "${REPO_NAME}.files"
    DB_MODIFIED=1
fi

if [ "${1:-}" = "--publish" ] && command -v gh >/dev/null 2>&1; then
    if [ "$DB_MODIFIED" -eq 1 ] || [ ${#BUILT_PKGS[@]} -gt 0 ]; then
        echo "=== Publishing to GitHub Releases ($ARCH) ==="
        if ! gh release view "$ARCH" >/dev/null 2>&1; then
            gh release create "$ARCH" --title "vero-on-arch ($ARCH)" --notes "Automated repository packages for $ARCH"
        fi

        UPLOAD_FILES=()
        for f in *.pkg.tar.zst "${REPO_NAME}.db" "${REPO_NAME}.db.tar.gz" "${REPO_NAME}.files" "${REPO_NAME}.files.tar.gz"; do
            [ -f "$f" ] && UPLOAD_FILES+=("$f")
        done

        if [ ${#UPLOAD_FILES[@]} -gt 0 ]; then
            gh release upload "$ARCH" "${UPLOAD_FILES[@]}" --clobber
            echo "Successfully published ${#UPLOAD_FILES[@]} assets to release $ARCH."
        fi
    fi
fi
