# Override COMPOSE when testing with an alternate Docker context or Compose wrapper.
COMPOSE="${COMPOSE:-docker compose}"
VOLUME_NAME="${JENKINS_HOME_VOLUME:-$(${COMPOSE} config --format json | jq -r '.volumes.jenkins_home.name // empty')}"
ENV_FILE ?= .env
SECRETS_DIR ?= secrets
AGENT_KEY ?= $(SECRETS_DIR)/jenkins_agent_key

.PHONY: init validate build up down logs ps backup restore clean

init:
	@if [ ! -f $(ENV_FILE) ]; then cp .env.example $(ENV_FILE); echo "Created $(ENV_FILE) from .env.example"; fi
	@mkdir -p $(SECRETS_DIR)
	@if [ ! -f $(AGENT_KEY) ]; then ssh-keygen -t ed25519 -f $(AGENT_KEY) -N '' -C jenkins-agent; fi
	@chmod 600 $(AGENT_KEY)
	@PUBKEY=$$(cat $(AGENT_KEY).pub); \
	  if grep -q "ssh-ed25519 REPLACE_WITH_PUBLIC_KEY jenkins-agent" $(ENV_FILE); then \
	    sed -i.bak "s|ssh-ed25519 REPLACE_WITH_PUBLIC_KEY jenkins-agent|$${PUBKEY}|" $(ENV_FILE); \
	    rm -f $(ENV_FILE).bak; \
	    echo "Updated JENKINS_AGENT_SSH_PUBKEY in $(ENV_FILE)"; \
	  else \
	    echo "JENKINS_AGENT_SSH_PUBKEY already customized. Current generated public key:"; \
	    cat $(AGENT_KEY).pub; \
	  fi

validate:
	# Run this before upgrades to catch Compose interpolation or syntax mistakes early.
	$(COMPOSE) config --quiet

build:
	$(COMPOSE) build jenkins-controller
	$(COMPOSE) build ci-arm64-general ci-arm64-alm
	$(COMPOSE) build ci-arm64-docker

up: build
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

backup:
	./backup/backup-jenkins-home.sh

restore:
	@test -n "$(ARCHIVE)" || (echo "Usage: make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz" && exit 2)
	$(COMPOSE) down
	CONFIRM_RESTORE=RESTORE ./backup/restore-jenkins-home.sh "$(ARCHIVE)"

clean:
	$(COMPOSE) down --remove-orphans
