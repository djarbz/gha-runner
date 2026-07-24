#!/usr/bin/env bash
set -euo pipefail

# Setup native registry proxy (replaces the old dind-proxy sidecar)
HOST_IP=$(ip route | awk '/default/ {print $3}')
socat TCP-LISTEN:5000,fork "TCP:${HOST_IP}:5000" >/dev/null 2>&1 &

# Tell the internal Docker daemon to trust our shared HTTP registry
sudo mkdir -p /etc/docker
sudo bash -c 'cat <<EOF > /etc/docker/daemon.json
{
  "insecure-registries": ["registry:5000"]
}
EOF'

# Remove stale PID/socket files from previous ephemeral runs
sudo rm -f /var/run/docker.pid /var/run/docker.sock

# Start the Docker daemon and explicitly route stdout/stderr to the container's PID 1 log stream
# By explicitly writing to /proc/1/fd/1 (Standard Out) and /proc/1/fd/2 (Standard Error),
#   you hardcode the daemon's output directly into the Docker logging engine itself.
# Shellcheck(SC2024): sudo doesn't affect redirects. Use ..| sudo tee file
# shellcheck disable=SC2024
sudo dockerd --host=unix:///var/run/docker.sock >/proc/1/fd/1 2>/proc/1/fd/2 &

# Wait for the Docker socket to become available
echo "Waiting for Docker daemon to initialize..."
while ! sudo docker info >/dev/null 2>&1; do
  sleep 1
done
echo "Docker daemon is up and running."

# Ensure the runner user has read/write access to the socket
sudo chmod 666 /var/run/docker.sock

# Hand off execution to your existing runner script
exec /home/runner/gha-runner.sh "$@"
