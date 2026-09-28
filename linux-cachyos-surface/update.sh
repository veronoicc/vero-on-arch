#!/usr/bin/env bash
set -euo pipefail

DIFF_OUTPUT="${1:-}"
UPDATED=0

while read -r name oldver arrow newver; do
    [ -n "$name" ] || continue

    if [ "$name" = "linux-surface" ] && [[ "$newver" =~ ^([0-9]+\.[0-9]+)\.?([0-9]*)-([0-9]+)$ ]]; then
        new_major="${BASH_REMATCH[1]}"
        new_minor="${BASH_REMATCH[2]:-0}"
        new_surface_rel="${BASH_REMATCH[3]}"
        echo "Updating linux-cachyos-surface: major=$new_major, minor=$new_minor, surface_rel=$new_surface_rel"
        sed -i -E "s/^(_major=).*/\1${new_major}/" PKGBUILD
        sed -i -E "s/^(_minor=).*/\1${new_minor}/" PKGBUILD
        sed -i -E "s/^(_surface_rel=).*/\1${new_surface_rel}/" PKGBUILD
        sed -i -E "s/^(pkgrel=).*/\11/" PKGBUILD

        # Check if CachyOS has a matching release tag for this kernel version
        tagrel=$(git ls-remote --tags https://github.com/CachyOS/linux.git "refs/tags/cachyos-${new_major}.${new_minor}-*" 2>/dev/null \
            | awk '{print $2}' | sed 's@refs/tags/cachyos-@@; s/\^.*//' \
            | sort -uV | tail -n1 | sed -E 's/.*-([0-9]+)$/\1/' || true)
        if [ -n "$tagrel" ]; then
            echo "Found CachyOS release tagrel: $tagrel"
            sed -i -E "s/^(_tagrel=).*/\1${tagrel}/" PKGBUILD
        fi

        if command -v nvtake >/dev/null 2>&1; then
            nvtake -c .nvchecker.toml "$name" || true
        fi
        UPDATED=1

    elif [ "$name" = "dylandhall-repo" ]; then
        echo "Upstream dylandhall repo updated, syncing configs..."
        curr_major="$(grep -E '^(_major=)' PKGBUILD | cut -d= -f2 || echo "6.19")"
        curl -LSsf "https://raw.githubusercontent.com/dylandhall/linux-cachyos-surface/main/linux-cachyos-surface/config" -o config || true
        curl -LSsf "https://raw.githubusercontent.com/dylandhall/linux-cachyos-surface/main/linux-cachyos-surface/surface-${curr_major}.config" -o "surface-${curr_major}.config" 2>/dev/null || true
        if command -v nvtake >/dev/null 2>&1; then
            nvtake -c .nvchecker.toml "$name" || true
        fi
        UPDATED=1
    fi
done <<< "$DIFF_OUTPUT"

if [ "$UPDATED" -eq 1 ]; then
    if command -v makepkg >/dev/null 2>&1; then
        makepkg --printsrcinfo > .SRCINFO 2>/dev/null || true
    fi
fi
