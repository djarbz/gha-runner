# warning: Using latest is prone to errors if the image will ever update. Pin the version explicitly to a release tag
# hadolint ignore=DL3007
FROM ghcr.io/actions/actions-runner:latest
LABEL org.opencontainers.image.source="https://github.com/djarbz/gha-runner"
LABEL org.opencontainers.image.description="A custom Self-Hosted GitHub Actions runner for single host Docker/Podman."
LABEL org.opencontainers.image.licenses="MIT"

COPY --chmod=755 ./gha-runner.sh /home/runner/gha-runner.sh
CMD ["/home/runner/gha-runner.sh"]
