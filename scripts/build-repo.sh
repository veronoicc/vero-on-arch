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
    eval "$(makepkg --printspec 2>/dev/null | grep -E '^(pkgname|pkgver|pkgrel)=')" || true
    if [ -z "$pkgname" ] || [ -z "$pkgver" ] || [ -z "$pkgrel" ]; then
        eval "$(grep -E '^(pkgname|pkgver|pkgrel)=' PKGBUILD)" || true
    fi

    echo "Package: $pkgname, Version: $pkgver-$pkgrel"

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

if [ ${#BUILT_PKGS[@]} -eq 0 ]; then
    echo "No new packages to add."
else
    echo "=== Updating repository database ==="
    repo-add "${REPO_NAME}.db.tar.gz" "${BUILT_PKGS[@]}"

    # Replace symlinks with real files for GitHub Releases compatibility
    cp -f --remove-destination "${REPO_NAME}.db.tar.gz" "${REPO_NAME}.db"
    cp -f --remove-destination "${REPO_NAME}.files.tar.gz" "${REPO_NAME}.files"
fi

if [ "${1:-}" = "--publish" ] && command -v gh >/dev/null 2>&1; then
    if [ ${#BUILT_PKGS[@]} -gt 0 ] || [ -f "$REPO_DB" ]; then
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
