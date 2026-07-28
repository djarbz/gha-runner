#!/usr/bin/env bash
set -euo pipefail

# Ensure the runner user has read/write access to the socket mapped from the host
# Note: This will alter the socket permissions on the host system.
sudo chmod 666 /var/run/docker.sock

# Hand off execution to your existing runner script
exec /home/runner/gha-runner.sh "$@"
