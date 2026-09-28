#!/usr/bin/env bash
set -e

# If RUNNER_TOKEN and REPO_URL are set, configure and run actions-runner
if [ -n "${RUNNER_TOKEN:-}" ] && [ -n "${REPO_URL:-}" ]; then
    RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
    RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,archlinux}"
    RUNNER_GROUP="${RUNNER_GROUP:-Default}"
    RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"

    cd /home/builder/actions-runner

    cleanup() {
        echo "Caught termination signal, removing runner from GitHub..."
        if [ -n "${REMOVE_TOKEN:-}" ]; then
            ./config.sh remove --token "${REMOVE_TOKEN}" || true
        elif [ -n "${RUNNER_TOKEN:-}" ]; then
            ./config.sh remove --token "${RUNNER_TOKEN}" || true
        fi
        exit 0
    }
    trap cleanup SIGTERM SIGINT

    # Configure runner if not already configured
    if [ ! -f .runner ]; then
        echo "Configuring GitHub Actions Runner for ${REPO_URL}..."
        ./config.sh \
            --url "${REPO_URL}" \
            --token "${RUNNER_TOKEN}" \
            --name "${RUNNER_NAME}" \
            --labels "${RUNNER_LABELS}" \
            --runnergroup "${RUNNER_GROUP}" \
            --work "${RUNNER_WORKDIR}" \
            --unattended \
            --replace
    fi

    echo "Starting GitHub Actions Runner..."
    exec ./run.sh
else
    # Fallback to executing command passed to container
    exec "$@"
fi
