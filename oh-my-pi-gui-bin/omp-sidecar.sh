#!/usr/bin/env bash
# Wrapper around system omp to filter flags unsupported by upstream (can1357/oh-my-pi)
_OMP="/usr/bin/omp"
if [ ! -x "$_OMP" ]; then
    _OMP="$(command -v omp || true)"
fi
if [ -z "$_OMP" ] || [ ! -x "$_OMP" ]; then
    echo "Error: omp binary not found in /usr/bin/omp or PATH" >&2
    exit 1
fi

args=()
for arg in "$@"; do
    case "$arg" in
        --no-auto-resume|--chat)
            # Upstream can1357/oh-my-pi does not support these flags
            ;;
        *)
            args+=("$arg")
            ;;
    esac
done

exec "$_OMP" "${args[@]}"
