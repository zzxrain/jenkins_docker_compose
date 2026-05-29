# Override COMPOSE when testing with an alternate Docker context or Compose wrapper.
COMPOSE ?= docker compose
ENV_FILE ?= .env
SECRETS_DIR ?= secrets
AGENT_KEY ?= $(SECRETS_DIR)/jenkins_agent_key

.PHONY: init validate build up down logs ps backup restore clean

init:
	# Bootstrap local-only files that must never be committed.
	@if [ ! -f $(ENV_FILE) ]; then cp .env.example $(ENV_FILE); echo "Created $(ENV_FILE) from .env.example"; fi
	@mkdir -p $(SECRETS_DIR)
	# Use ed25519 for a compact modern SSH key dedicated to Jenkins agent connections.
	@if [ ! -f $(AGENT_KEY) ]; then ssh-keygen -t ed25519 -f $(AGENT_KEY) -N '' -C jenkins-agent; fi
	@chmod 600 $(AGENT_KEY)
	@echo "Set JENKINS_AGENT_SSH_PUBKEY in $(ENV_FILE) to:" && cat $(AGENT_KEY).pub

validate:
	# Run this before upgrades to catch Compose interpolation or syntax mistakes early.
	$(COMPOSE) config --quiet

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

backup:
	./backup/backup-jenkins-home.sh

restore:
	# Require an explicit archive path so restore operations are intentional and auditable.
	@test -n "$(ARCHIVE)" || (echo "Usage: make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz" && exit 2)
	CONFIRM_RESTORE=RESTORE ./backup/restore-jenkins-home.sh "$(ARCHIVE)"

clean:
	$(COMPOSE) down --remove-orphans
