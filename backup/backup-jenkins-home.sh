#!/usr/bin/env bash
set -euo pipefail

# Allow callers to redirect backup output without editing the script.
BACKUP_DIR="${BACKUP_DIR:-./backup/output}"
TS="$(date +%Y%m%d-%H%M%S)"
# Resolve the actual Compose volume name so project-name changes do not break backups.
VOLUME_NAME="${JENKINS_HOME_VOLUME:-$(docker compose config --format json | jq -r '.volumes.jenkins_home.name // empty')}"

if [[ -z "${VOLUME_NAME}" ]]; then
  echo "Unable to determine Jenkins home volume name. Set JENKINS_HOME_VOLUME manually." >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# Run tar in a short-lived container to avoid requiring tar access on the Docker host volume path.
docker run --rm \
  -v "${VOLUME_NAME}:/var/jenkins_home:ro" \
  -v "$(pwd)/${BACKUP_DIR}:/backup" \
  alpine:3.20 \
  tar czf "/backup/jenkins_home_${TS}.tar.gz" -C /var/jenkins_home .

echo "Backup created: ${BACKUP_DIR}/jenkins_home_${TS}.tar.gz"
