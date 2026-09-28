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

# Configure compiler cache if ccache is available
if command -v ccache >/dev/null 2>&1; then
    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache}"
    mkdir -p "$CCACHE_DIR" "$HOME/.config/ccache"
    if [ ! -f "$HOME/.config/ccache/ccache.conf" ]; then
        cat << 'EOF' > "$HOME/.config/ccache/ccache.conf"
max_size = 50G
sloppiness = time_macros,include_file_mtime,file_macro
hash_dir = false
EOF
    fi
    if [ ! -f "$HOME/.makepkg.conf" ] && [ -f /etc/makepkg.conf ]; then
        cp /etc/makepkg.conf "$HOME/.makepkg.conf" 2>/dev/null || true
    fi
    if [ -f "$HOME/.makepkg.conf" ]; then
        sed -i 's/!ccache/ccache/' "$HOME/.makepkg.conf"
        sed -i 's/^#*COMPRESSZST=.*/COMPRESSZST=(zstd -c -z -q -T0 -1)/' "$HOME/.makepkg.conf"
    fi
fi

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

    pkg_list=()
    mapfile -t pkg_list < <(makepkg --packagelist 2>/dev/null || true)

    current_pkg_names=()
    all_in_db=1
    first_pkgver=""
    first_pkgrel=""

    for pkgpath in "${pkg_list[@]}"; do
        [ -n "$pkgpath" ] || continue
        pkgfile="$(basename "$pkgpath")"
        if [[ "$pkgfile" =~ ^(.+)-([^-]+)-([^-]+)-([^-]+)\.pkg\.tar\.(zst|xz|gz)$ ]]; then
            pname="${BASH_REMATCH[1]}"
            pver="${BASH_REMATCH[2]}"
            prel="${BASH_REMATCH[3]}"
            current_pkg_names+=("$pname")
            KNOWN_PKGS+=("$pname")
            if [ -z "$first_pkgver" ]; then
                first_pkgver="$pver"
                first_pkgrel="$prel"
            fi
            if [ ! -f "$REPO_DB" ] || ! tar -ztf "$REPO_DB" 2>/dev/null | grep -qx "${pname}-${pver}-${prel}/"; then
                all_in_db=0
            fi
        fi
    done

    # Fallback if packagelist was empty
    if [ ${#current_pkg_names[@]} -eq 0 ]; then
        read -r pkgname pkgver pkgrel < <(bash -c 'source ./PKGBUILD 2>/dev/null; echo "${pkgname:-} ${pkgver:-} ${pkgrel:-}"' || true)
        current_pkg_names+=("$pkgname")
        KNOWN_PKGS+=("$pkgname")
        first_pkgver="$pkgver"
        first_pkgrel="$pkgrel"
        if [ ! -f "$REPO_DB" ] || ! tar -ztf "$REPO_DB" 2>/dev/null | grep -qx "${pkgname}-${pkgver}-${pkgrel}/"; then
            all_in_db=0
        fi
    fi

    echo "Package(s): ${current_pkg_names[*]}, Version: $first_pkgver-$first_pkgrel"

    # Check if all packages for this version already exist in repo database
    if [ "$all_in_db" -eq 1 ] && [ -f "$REPO_DB" ]; then
        echo "All packages for $pkgname_dir ($first_pkgver-$first_pkgrel) are already in repository database. Skipping build."
        continue
    fi

    echo "Building ${current_pkg_names[*]}..."
    rm -f *.pkg.tar.zst src pkg -rf

    BUILD_SUCCESS=0
    # Install packages built in earlier steps of this run so intra-repo dependencies resolve
    if compgen -G "$DIST_DIR/*.pkg.tar.zst" > /dev/null; then
        sudo pacman -U --noconfirm --needed "$DIST_DIR"/*.pkg.tar.zst 2>/dev/null || true
    fi

    echo "Building with makepkg..."
    if makepkg -s --noconfirm; then
        BUILD_SUCCESS=1
    elif makepkg -d --noconfirm; then
        echo "makepkg -s failed (likely intra-repo runtime dependencies), built with makepkg -d."
        BUILD_SUCCESS=1
    elif command -v yay >/dev/null 2>&1; then
        echo "makepkg failed or needs AUR dependencies, retrying with yay..."
        if yay -B . --noconfirm; then
            BUILD_SUCCESS=1
        fi
    fi
    if [ "$BUILD_SUCCESS" -ne 1 ]; then
        echo "Failed to build ${current_pkg_names[*]}" >&2
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
                mapfile -t ASSETS_TO_DELETE < <(gh release view "$ARCH" --json assets --jq ".assets[].name" 2>/dev/null | grep -E "^${db_pkg}-[0-9]" || true)
                for asset in "${ASSETS_TO_DELETE[@]}"; do
                    [ -n "$asset" ] || continue
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
