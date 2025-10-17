# gha-runner

**CREATE** `Github PAT: Fine-grained tokens`\
**SET** *PAT* `Actions: RW`\
**SET** *PAT* `Administration: RW` NOTE: Need to verify if `W` is needed.\
**SET** `.env` with your Github *PAT*\
**SET** `.env` with your Github Repository `namespace/repo`\
**SET** Docker Compose Deploy Replica count for additional runners.\
**RUN** `docker compose up -d; docker compose logs -f`\
**SET** *WORKFLOW* *JOB* `runs-on: [self-hosted, linux]`
