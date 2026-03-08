# warning: Using latest is prone to errors if the image will ever update. Pin the version explicitly to a release tag
# hadolint ignore=DL3007
FROM ghcr.io/actions/actions-runner:latest
LABEL org.opencontainers.image.source="https://github.com/djarbz/gha-runner"
LABEL org.opencontainers.image.description="A custom Self-Hosted GitHub Actions runner for single host Docker/Podman."
LABEL org.opencontainers.image.licenses="MIT"

# Switch to root to install system packages
USER root

# Set shell to bash with pipefail to catch errors in piped commands
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install GitHub CLI (gh)
# hadolint ignore=DL3008
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch back to the default runner user for security
USER runner

COPY --chmod=755 ./gha-runner.sh /home/runner/gha-runner.sh
CMD ["/home/runner/gha-runner.sh"]
