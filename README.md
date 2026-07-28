# gha-runner

**CREATE** `Github PAT: Fine-grained tokens`\
**SET** _PAT_ `Actions: RW`\
**SET** _PAT_ `Administration: RW` NOTE: Need to verify if `W` is needed.\
**SET** `.env` with your Github _PAT_
**SET** `.env` with your Github Repository `namespace/repo`
**SET** `.env` with the number of `REPLICAS` for each project.
**RUN** `docker compose up -d; docker compose logs -f`
**SET** _WORKFLOW_ _JOB_ `runs-on: [self-hosted, linux]`

---

## Architecture Overview

This project provides a robust, self-hosted GitHub Actions runner environment utilizing a **Docker-out-of-Docker (DooD)** architecture. By passing the host's Docker socket into the runner container, it securely controls the host's Docker daemon. This setup takes full advantage of native host performance and storage caching while routing build caches to a single, globally shared registry on the host VM.

### Component Breakdown

The architecture is split into two primary components: the Global Registry and the Runner Stacks.

**1. Global Shared Registry (`example_layout/build-cache/registry.docker-compose.yaml`)**
Runs a single central `registry:2` container directly on the host VM, exposing port `5000`. This provides a single deduplicated cache layer for all runner stacks, drastically speeding up build times for workflows relying on native Docker caching.

**2. Runner Stack (`example_layout/runner.template.docker-compose.yaml`)**
Each repository or runner namespace gets its own stack composed of a single, highly-efficient `runner` service. It runs the core worker utilizing the custom `ghcr.io/djarbz/gha-runner:latest` image. Instead of nested containers, it mounts the host's `/var/run/docker.sock`, allowing the runner to spawn ephemeral container jobs directly on the host machine using native storage.

It is recommended to save this structure in your workspace root directory and link the template into each project.

```text
.
├── build-cache/
│   ├── cleanup.sh
│   └── docker-compose.yaml
├── project01/
│   ├── docker-compose.yaml -> ../runner.template.docker-compose.yaml
│   └── .env
├── project02/
│   ├── docker-compose.yaml -> ../runner.template.docker-compose.yaml
│   └── .env
├── project03/
│   ├── docker-compose.yaml -> ../runner.template.docker-compose.yaml
│   └── .env
├── restart.sh
├── runner.template.docker-compose.yaml
└── update.sh
```

---

## Automation & Maintenance Scripts

To keep the host VM lean and automatically up-to-date, this repository includes several automated maintenance scripts located at the root and cache levels:

- **`cleanup.sh`**: A smart garbage collection routine designed to prevent disk space exhaustion. It scans the global registry logs to identify active caches referenced within the last 30 days, surgically deletes abandoned caches, executes native registry garbage collection, and runs a `docker system prune` on the host to purge temporary job containers and dangling images older than 7 days.
- **`update.sh`**: A continuous deployment script (ideal for cron jobs) that checks for new versions of the runner. It compares the local image ID of `ghcr.io/djarbz/gha-runner:latest` against the remote registry. If an update is detected, it pulls the new image, iterates through all stack directories in `/docker/gha-runner`, and gracefully restarts them with `docker compose up -d`.
- **`restart.sh`**: A utility script to perform a rolling restart across all runner projects. It iterates through your target directories and triggers a clean `docker compose restart` for each stack.

It is recommended to schedule the `update.sh` and `cleanup.sh` scripts to run on a schedule.
All scripts output to journald for centralized storage and access.

```bash
# View only the update routine logs
journalctl -t gha-runner-update -e

# View only the smart cache pruning logs
journalctl -t gha-runner-cleanup -e

# View only the runner stack rolling restart logs
journalctl -t gha-runner-restart -e

# Follow all custom logs seamlessly in real-time
journalctl -t gha-runner-update -t gha-runner-cleanup -t gha-runner-restart -f
```
