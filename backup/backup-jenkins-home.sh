#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="./backup/output"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "${BACKUP_DIR}"

docker run --rm \
  -v jenkins-docker_jenkins_home:/var/jenkins_home:ro \
  -v "$(pwd)/${BACKUP_DIR}:/backup" \
  alpine:3.20 \
  tar czf "/backup/jenkins_home_${TS}.tar.gz" -C /var/jenkins_home .

echo "Backup created: ${BACKUP_DIR}/jenkins_home_${TS}.tar.gz"