# gha-runner

**CREATE** `Github PAT: Fine-grained tokens`\
**SET** *PAT* `Actions: RW`\
**SET** *PAT* `Administration: RW` NOTE: Need to verify if `W` is needed.\
**SET** `.env` with your Github *PAT*\
**SET** `.env` with your Github Repository `namespace/repo`\
**SET** `.env` with the number of `REPLICAS` for each project.\
**RUN** `docker compose up -d; docker compose logs -f`\
**SET** *WORKFLOW* *JOB* `runs-on: [self-hosted, linux]`

---

## Architecture Overview

This project provides a robust, self-hosted GitHub Actions runner environment utilizing a **Docker-in-Docker (DinD)** architecture. This setup securely isolates GitHub Actions job executions while solving standard nested-container caching issues by routing all build caches to a single, globally shared registry on the host VM.

### Component Breakdown

The architecture is split into two primary components: the Global Registry and the Runner Stacks.

**1. Global Shared Registry (`docker/shared_registry/registry.docker-compose.yaml`)**

* Runs a single central `registry:2` container directly on the host VM, exposing port `5000`.
* This provides a single deduplicated cache layer for all runner stacks, drastically speeding up build times for workflows relying on tools like `buildah` and `buildx`.

**2. Runner Stack (`docker/shared_registry/runner.docker-compose.yaml`)**
Each repository or runner namespace gets its own stack composed of three tightly integrated services:

* **`dind`**: A privileged `docker:dind` container that acts as the isolated Docker daemon for this specific runner stack. It prevents workflow jobs from colliding or gaining access to the host's root filesystem.
* **`runner`**: The core worker running the custom `ghcr.io/djarbz/gha-runner:latest` image. It connects securely to the `dind` daemon via TLS on port `2376` and shares specific path volumes (like `runner-externals` and `runner-work`) to ensure GitHub Actions' bundled Node.js binaries and cloned repositories are mapped correctly into job containers.
* **`dind-proxy`**: An Alpine-based networking proxy that bridges the DinD isolation barrier. Because job containers run *inside* the `dind` network, they cannot naturally resolve the host VM's global registry. This proxy sits on the gateway, uses `socat` to intercept traffic on port 5000, and dynamically routes it out to the host VM's IP address.

It is recommended to save this runner in your workspace root directory and link it into each project.

```bash
root@gha-runner:/opt/gha-runners# tree
.
├── cleanup.sh
├── project1/
│   ├── .env
│   ├── docker-compose.yaml -> ../runner.docker-compose.template.yaml
├── project2/
│   ├── .env
│   ├── docker-compose.yaml -> ../runner.docker-compose.template.yaml
├── project3/
│   ├── .env
│   ├── docker-compose.yaml -> ../runner.docker-compose.template.yaml
├── global-registry/
│   └── docker-compose.yaml
├── restart.sh
├── runner.docker-compose.template.yaml
└── update.sh
```

---

## Automation & Maintenance Scripts

To keep the host VM lean and automatically up-to-date, this repository includes several automated maintenance scripts located in the `scripts/` directory:

* **`cleanup.sh`**: A smart garbage collection routine designed to prevent disk space exhaustion.
  * It scans the global registry logs to identify active caches referenced within the last 30 days and surgically deletes abandoned caches.
  * It executes native registry garbage collection to free up disk space.
  * It loops through the host daemon and every running DinD container (`ancestor=docker:dind`) to run a `docker system prune`, purging temporary job containers and dangling images older than 7 days.
* **`update.sh`**: A continuous deployment script (ideal for cron jobs) that checks for new versions of the runner.
  * It compares the local image ID of `ghcr.io/djarbz/gha-runner:latest` against the remote registry.
  * If an update is detected, it pulls the new image and iterates through all stack directories in `/docker` to gracefully restart them with `docker compose up -d`.
* **`restart.sh`**: A utility script to perform a rolling restart across all runner project.
  * It initiates restarts and then actively monitors the `healthcheck` status of all DinD containers until they report as `healthy`.
  * Once healthy, it performs a local image prune inside the nested daemons to clear up immediate bloat.

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
