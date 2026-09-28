#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -n "${GITHUB_TOKEN:-}" ]; then
    mkdir -p "$HOME/.config/nvchecker"
    cat << EOF > "$HOME/.config/nvchecker/keyfile.toml"
[keys]
github = "${GITHUB_TOKEN}"
EOF
fi

UPDATED=0

for pkgdir in "$REPO_ROOT"/*/; do
    [ -d "$pkgdir" ] || continue
    [ -f "${pkgdir}PKGBUILD" ] || continue

    pkgname_dir="$(basename "$pkgdir")"
    if [ "$pkgname_dir" = "dist" ] || [ "$pkgname_dir" = "scripts" ]; then
        continue
    fi

    echo ":: Checking updates for package: $pkgname_dir"
    cd "$pkgdir"

    # Determine if package is a VCS package (defines pkgver())
    is_vcs=0
    if grep -qE '^[[:space:]]*pkgver\(\)' PKGBUILD; then
        is_vcs=1
    fi

    # Manifest-based checking (nvchecker)
    nvconf=""
    if [ -f ".nvchecker.toml" ]; then
        nvconf=".nvchecker.toml"
    elif [ -f "nvchecker.toml" ]; then
        nvconf="nvchecker.toml"
    fi

    if [ -n "$nvconf" ] && command -v nvchecker >/dev/null 2>&1; then
        echo "Running nvchecker with $nvconf..."
        nvchecker -c "$nvconf" || true

        diff_output=""
        if command -v nvcmp >/dev/null 2>&1; then
            diff_output="$(nvcmp -c "$nvconf" || true)"
        fi

        if [ -n "$diff_output" ]; then
            echo "nvchecker found updates for $pkgname_dir:"
            echo "$diff_output"
            if [ -x "./update.sh" ]; then
                echo "Running package-specific update hook for $pkgname_dir..."
                if ./update.sh "$diff_output"; then
                    UPDATED=1
                fi
            elif [ "$is_vcs" -eq 1 ]; then
                echo "VCS package with upstream updates detected. Updating pkgver via makepkg..."
                makepkg -od --nodeps --skipinteg 2>&1 || true
                rm -rf src/ pkg/ *.part
                if command -v nvtake >/dev/null 2>&1; then
                    nvtake -c "$nvconf" --all || true
                fi
                if ! git diff --quiet PKGBUILD; then
                    echo "VCS version updated for $pkgname_dir"
                    makepkg --printsrcinfo > .SRCINFO 2>/dev/null || true
                    UPDATED=1
                fi
            else
                while read -r name oldver arrow newver; do
                    if [ -n "$newver" ]; then
                        echo "Updating $name to $newver in PKGBUILD"
                        sed -i -E "s/^(pkgver=).*/\1${newver}/" PKGBUILD
                        sed -i -E "s/^(pkgrel=).*/\11/" PKGBUILD
                        if command -v updpkgsums >/dev/null 2>&1; then
                            updpkgsums || true
                        fi
                        if command -v nvtake >/dev/null 2>&1; then
                            nvtake -c "$nvconf" "$name" || true
                        fi
                        makepkg --printsrcinfo > .SRCINFO 2>/dev/null || true
                        UPDATED=1
                    fi
                done <<< "$diff_output"
            fi
        else
            echo "No upstream updates detected by nvchecker for $pkgname_dir."
        fi
    elif [ "$is_vcs" -eq 1 ]; then
        echo "Detected VCS package without nvchecker config. Updating pkgver..."
        makepkg -od --nodeps --skipinteg 2>&1 || true
        rm -rf src/ pkg/ *.part
        if ! git diff --quiet PKGBUILD; then
            echo "VCS version updated for $pkgname_dir"
            makepkg --printsrcinfo > .SRCINFO 2>/dev/null || true
            UPDATED=1
        fi
    fi
    cd "$REPO_ROOT"
done

if [ "$UPDATED" -eq 1 ]; then
    echo "Package versions updated."
    if [ "${1:-}" = "--commit" ]; then
        git config user.name "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git add -u
        git add '*/oldver.json' '*/.SRCINFO' 2>/dev/null || true
        if ! git diff --cached --quiet; then
            git commit -m "chore(repo): auto-update package versions"
            git push origin main
        fi
    fi
else
    echo "No package updates detected."
fi
