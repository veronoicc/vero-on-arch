#!/usr/bin/env sh
# Find electron binary
if [ -n "$ELECTRON_PATH" ] && command -v "$ELECTRON_PATH" >/dev/null 2>&1; then
    _ELECTRON="$ELECTRON_PATH"
elif command -v electron >/dev/null 2>&1; then
    _ELECTRON=electron
else
    for _v in 44 43 42 41 40 39 38 37 36; do
        if command -v "electron$_v" >/dev/null 2>&1; then
            _ELECTRON="electron$_v"
            break
        fi
    done
fi

if [ -z "$_ELECTRON" ]; then
    echo "Error: electron executable not found" >&2
    exit 1
fi

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
_FLAGS_FILE="$XDG_CONFIG_HOME/omp-gui-flags.conf"
if [ -r "$_FLAGS_FILE" ]; then
    _USER_FLAGS="$(grep -v '^#' "$_FLAGS_FILE")"
fi

exec "$_ELECTRON" /usr/lib/oh-my-pi-gui $_USER_FLAGS "$@"
