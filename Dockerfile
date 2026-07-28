# warning: Using latest is prone to errors if the image will ever update. Pin the version explicitly to a release tag
# hadolint ignore=DL3007
FROM ghcr.io/actions/actions-runner:latest
LABEL org.opencontainers.image.source="https://github.com/djarbz/gha-runner"
LABEL org.opencontainers.image.description="A custom Self-Hosted GitHub Actions runner using DooD."
LABEL org.opencontainers.image.licenses="MIT"

# Switch to root to install system packages
USER root

# Set shell to bash with pipefail to catch errors in piped commands
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Backup the built-in externals so they aren't lost when the host bind-mounts an empty directory
RUN cp -a /home/runner/externals /home/runner/externals_backup && \
    chown -R runner:docker /home/runner/externals_backup

# Install GitHub CLI (gh), procps, iptables, and Docker
# hadolint ignore=DL3008
RUN <<EORUN
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg procps sudo iproute2

curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y --no-install-recommends docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin gh

usermod -aG docker runner
echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

apt-get clean
rm -rf /var/lib/apt/lists/*
EORUN

# Switch back to the default runner user for security
USER runner

# Add Healthcheck to monitor the Runner.Listener process
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD pgrep -f "Runner.Listener" > /dev/null || exit 1

# Copy the wrapper and the runner script
COPY --chmod=755 ./entrypoint.sh /home/runner/entrypoint.sh
COPY --chmod=755 ./gha-runner.sh /home/runner/gha-runner.sh

# Use the wrapper as the primary command
CMD ["/home/runner/entrypoint.sh"]
