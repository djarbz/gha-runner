#!/usr/bin/env bash
set -euo pipefail

# Ensure the runner user has read/write access to the socket mapped from the host
# Note: This will alter the socket permissions on the host system.
sudo chmod 666 /var/run/docker.sock

# Populate the host's empty bind-mounted externals directory with the built-in Node binaries
if [ -z "$(ls -A /home/runner/externals)" ]; then
  echo "Populating empty externals directory..."
  cp -a /home/runner/externals_backup/* /home/runner/externals/
fi

# Hand off execution to your existing runner script
exec /home/runner/gha-runner.sh "$@"
