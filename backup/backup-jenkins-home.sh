#!/usr/bin/env bash
set -euo pipefail

# Keep large runtime backups outside the Git working tree by default. Callers
# can still override BACKUP_DIR with another absolute or relative directory.
BACKUP_DIR="${BACKUP_DIR:-${HOME}/DevTools/Backup/jenkins-docker}"
TS="$(date +%Y%m%d-%H%M%S)"
# Resolve the actual Compose volume name so project-name changes do not break backups.
COMPOSE="${COMPOSE:-docker compose}"
VOLUME_NAME="${JENKINS_HOME_VOLUME:-$(${COMPOSE} config --format json | jq -r '.volumes.jenkins_home.name // empty')}"

if [[ -z "${VOLUME_NAME}" ]]; then
  echo "Unable to determine Jenkins home volume name. Set JENKINS_HOME_VOLUME manually." >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
# Docker bind mounts are clearer and safer with a normalized absolute path.
BACKUP_DIR="$(cd "${BACKUP_DIR}" && pwd -P)"

# Run tar in a short-lived container to avoid requiring tar access on the Docker host volume path.
docker run --rm \
  -v "${VOLUME_NAME}:/var/jenkins_home:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine:3.20 \
  tar czf "/backup/jenkins_home_${TS}.tar.gz" -C /var/jenkins_home .

echo "Backup created: ${BACKUP_DIR}/jenkins_home_${TS}.tar.gz"
