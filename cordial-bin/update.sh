#!/usr/bin/env bash
set -euo pipefail

DIFF_OUTPUT="${1:-}"
UPDATED=0

while read -r name oldver arrow newver; do
    [ -n "$name" ] || continue

    if [ "$name" = "cordial-bin" ] && [ -n "$newver" ]; then
        echo "Resolving upstream release asset for cordial-bin v${newver}..."
        asset=""
        auth_header=()
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
        fi

        # Try GitHub API first
        api_url="https://api.github.com/repos/luohoa97/cordial/releases/tags/v${newver}"
        asset=$(curl -fsSL "${auth_header[@]}" "$api_url" 2>/dev/null \
            | grep -oE '"name": "[^"]+-1-x86_64\.pkg\.tar\.zst"' \
            | head -n 1 | cut -d'"' -f4 || true)

        # Fallback to expanded_assets HTML scraping if API fails (e.g. rate limit)
        if [ -z "$asset" ]; then
            html_url="https://github.com/luohoa97/cordial/releases/expanded_assets/v${newver}"
            asset=$(curl -fsSL "$html_url" 2>/dev/null \
                | grep -oE 'cordial-[^"'\''[:space:]]+-1-x86_64\.pkg\.tar\.zst' \
                | head -n 1 || true)
        fi

        if [ -z "$asset" ]; then
            echo "Error: Failed to resolve x86_64 package asset for version ${newver}" >&2
            exit 1
        fi

        echo "Found asset: $asset"
        sed -i -E "s/^(pkgver=).*/\1${newver}/" PKGBUILD
        sed -i -E "s/^(pkgrel=).*/\11/" PKGBUILD
        sed -i -E "s/^(_asset=).*/\1\"${asset}\"/" PKGBUILD

        if command -v updpkgsums >/dev/null 2>&1; then
            updpkgsums
        fi

        if command -v nvtake >/dev/null 2>&1; then
            nvtake -c .nvchecker.toml "$name" || true
        fi

        if command -v makepkg >/dev/null 2>&1; then
            makepkg --printsrcinfo > .SRCINFO
        fi

        UPDATED=1
    fi
done <<< "$DIFF_OUTPUT"

if [ "$UPDATED" -eq 1 ]; then
    echo "cordial-bin successfully updated."
    exit 0
else
    echo "No relevant updates processed for cordial-bin."
    exit 0
fi
