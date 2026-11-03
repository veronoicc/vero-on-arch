#!/usr/bin/env sh
export OMP_BUNDLED_OMP="${OMP_BUNDLED_OMP:-/opt/omp/resources/omp}"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
_FLAGS_FILE="$XDG_CONFIG_HOME/omp-gui-flags.conf"
if [ -r "$_FLAGS_FILE" ]; then
    _USER_FLAGS="$(grep -v '^#' "$_FLAGS_FILE")"
fi

exec /opt/omp/omp-gui $_USER_FLAGS "$@"
