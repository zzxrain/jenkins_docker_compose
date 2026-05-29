#!/usr/bin/env bash
set -euo pipefail

# Restore requires an explicit archive argument to avoid accidentally replaying the wrong backup.
ARCHIVE="${1:-}"
# Resolve the actual Compose volume name so project-name changes do not break restores.
COMPOSE="${COMPOSE:-docker compose}"
VOLUME_NAME="${JENKINS_HOME_VOLUME:-$(${COMPOSE} config --format json | jq -r '.volumes.jenkins_home.name // empty')}"

if [[ -z "${ARCHIVE}" || ! -f "${ARCHIVE}" ]]; then
  echo "Usage: CONFIRM_RESTORE=RESTORE $0 backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz" >&2
  exit 2
fi

# Use an environment guard so CI/non-interactive runs must opt in to destructive restore behavior.
if [[ "${CONFIRM_RESTORE:-}" != "RESTORE" ]]; then
  echo "Refusing to restore without CONFIRM_RESTORE=RESTORE." >&2
  echo "Stop Jenkins first with: docker compose down" >&2
  exit 2
fi

if [[ -z "${VOLUME_NAME}" ]]; then
  echo "Unable to determine Jenkins home volume name. Set JENKINS_HOME_VOLUME manually." >&2
  exit 1
fi

# Clear the volume before extraction so deleted files do not survive across restores.
docker run --rm \
  -v "${VOLUME_NAME}:/var/jenkins_home" \
  -v "$(pwd):/repo:ro" \
  alpine:3.20 \
  sh -c 'rm -rf /var/jenkins_home/* /var/jenkins_home/.[!.]* /var/jenkins_home/..?* 2>/dev/null || true; tar xzf "/repo/'"${ARCHIVE}"'" -C /var/jenkins_home'

echo "Restore completed into ${VOLUME_NAME}."
