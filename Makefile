# Override COMPOSE when testing with an alternate Docker context or Compose wrapper.
COMPOSE ?= docker compose

ENV_FILE ?= .env
SECRETS_DIR ?= secrets
CERTS_DIR ?= certs
AGENT_KEY ?= $(SECRETS_DIR)/jenkins_agent_key

CONTROLLER_IMAGE ?= local/jenkins-controller:2.555.2-lts-jdk21
AGENT_BASE_IMAGE ?= local/jenkins-ssh-agent-base:debian-jdk21
AGENT_DOCKER_IMAGE ?= local/jenkins-ssh-agent-docker:debian-jdk21

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make init                 Initialize .env and SSH key material"
	@echo "  make validate             Validate docker compose configuration"
	@echo "  make build                Build all images with normal cache"
	@echo "  make rebuild-controller   Rebuild Jenkins controller image with --no-cache"
	@echo "  make rebuild-agent-base   Rebuild base SSH agent image with --no-cache"
	@echo "  make rebuild-agent-docker Rebuild Docker-capable SSH agent image with --no-cache"
	@echo "  make rebuild-agents       Rebuild all agent images in the correct order"
	@echo "  make up                   Build with cache and start all services"
	@echo "  make down                 Stop services"
	@echo "  make clean                Stop services and remove orphan containers"
	@echo "  make reset                Remove services, networks, and project volumes"
	@echo "  make reset-images         Remove local images built by this project"
	@echo "  make reset-all            Reset volumes and remove local images"
	@echo "  make ps                   Show service status"
	@echo "  make logs                 Follow logs"
	@echo "  make verify               Verify controller plugins and security config"
	@echo "  make verify-volumes       Show container mounts and verify no anonymous volumes"
	@echo "  make verify-agents        Check controller-to-agent TCP connectivity"
	@echo "  make verify-docker-agent  Check Docker CLI access inside docker-capable agent"
	@echo "  make export-caddy-root    Export Caddy local root CA certificate"
	@echo "  make backup               Backup Jenkins home"
	@echo "  make restore ARCHIVE=...  Restore Jenkins home from backup"
	@echo "  make prune-volumes        Prune unused Docker volumes"

.PHONY: init
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

.PHONY: validate
validate:
	# Run this before upgrades to catch Compose interpolation or syntax mistakes early.
	$(COMPOSE) config --quiet

.PHONY: build build-controller build-agent-base build-agent-docker build-agents
build: build-controller build-agents

build-controller:
	$(COMPOSE) build jenkins-controller

# ci-arm64-general and ci-arm64-alm share the same image:
# local/jenkins-ssh-agent-base:debian-jdk21
# Building ci-arm64-general is enough to materialize the shared base image.
build-agent-base:
	$(COMPOSE) build ci-arm64-general

# This image depends on the locally built AGENT_BASE_IMAGE.
# Do not use --pull here, otherwise Docker may try to pull docker.io/local/...
build-agent-docker:
	$(COMPOSE) build ci-arm64-docker

build-agents: build-agent-base build-agent-docker

.PHONY: rebuild-controller rebuild-agent-base rebuild-agent-docker rebuild-agents
rebuild-controller:
	$(COMPOSE) --progress=plain build --no-cache --pull jenkins-controller

# Rebuild base SSH agent from the remote Jenkins ssh-agent image.
rebuild-agent-base:
	$(COMPOSE) --progress=plain build --no-cache --pull --no-deps ci-arm64-general

# Rebuild Docker-capable agent from the locally built base agent image.
# Important: no --pull here because FROM local/jenkins-ssh-agent-base:debian-jdk21 is local-only.
rebuild-agent-docker:
	$(COMPOSE) --progress=plain build --no-cache --no-deps ci-arm64-docker

rebuild-agents: rebuild-agent-base rebuild-agent-docker

.PHONY: up down clean reset reset-images reset-all
up: build
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --remove-orphans

# Remove project containers, network, and named volumes.
# This deletes Jenkins home, agent workspaces, and Caddy CA data.
reset:
	$(COMPOSE) down -v --remove-orphans

# Remove only project-built local images.
reset-images:
	-docker image rm $(CONTROLLER_IMAGE)
	-docker image rm $(AGENT_DOCKER_IMAGE)
	-docker image rm $(AGENT_BASE_IMAGE)

reset-all: reset reset-images

.PHONY: ps logs
ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=200

.PHONY: verify
verify:
	$(COMPOSE) exec jenkins-controller bash -lc '\
	echo "==== ref plugins ===="; \
	find /usr/share/jenkins/ref/plugins -maxdepth 1 -type f | sed "s#.*/##" | sort | grep -Ei "configuration-as-code|matrix-auth|ssh-slaves|credentials" || true; \
	echo; \
	echo "==== home plugins ===="; \
	find /var/jenkins_home/plugins -maxdepth 1 -type f | sed "s#.*/##" | sort | grep -Ei "configuration-as-code|matrix-auth|ssh-slaves|credentials" || true; \
	echo; \
	echo "==== security ===="; \
	grep -nE "useSecurity|securityRealm|authorizationStrategy" /var/jenkins_home/config.xml || true \
	'

.PHONY: verify-volumes
verify-volumes:
	$(COMPOSE) ps -a
	@echo
	@echo "==== volume and tmpfs mounts ===="
	@docker ps -a \
	  --filter name=jenkins-controller \
	  --filter name=jenkins-caddy \
	  --filter name=ci-arm64 \
	  --format '{{.Names}}' \
	| xargs docker inspect \
	| jq -r '\
	  .[] | \
	  .Name as $$container | \
	  .Config.Image as $$image | \
	  .Mounts[]? | \
	  [$$container, $$image, .Type, (.Name // "-"), .Destination] | @tsv \
	' | column -t
	@echo
	@echo "==== project volumes ===="
	@docker volume ls --filter label=app=jenkins-compose

.PHONY: verify-agents
verify-agents:
	$(COMPOSE) exec jenkins-controller bash -lc '\
	for h in ci-arm64-general ci-arm64-alm ci-arm64-docker; do \
	  echo "==== $$h ===="; \
	  getent hosts "$$h" || true; \
	  timeout 5 bash -lc "cat < /dev/null > /dev/tcp/$$h/22" \
	    && echo "$$h:22 OK" \
	    || echo "$$h:22 FAILED"; \
	done \
	'

.PHONY: verify-docker-agent
verify-docker-agent:
	$(COMPOSE) exec ci-arm64-docker bash -lc '\
	echo "DOCKER_HOST=$$DOCKER_HOST"; \
	docker version; \
	docker buildx version; \
	docker compose version \
	'

.PHONY: export-caddy-root
export-caddy-root:
	@mkdir -p $(CERTS_DIR)
	$(COMPOSE) cp caddy:/data/caddy/pki/authorities/local/root.crt ./$(CERTS_DIR)/caddy-local-root.crt
	openssl x509 \
	  -in ./$(CERTS_DIR)/caddy-local-root.crt \
	  -noout \
	  -subject \
	  -issuer \
	  -dates \
	  -fingerprint \
	  -sha256

.PHONY: backup restore
backup:
	COMPOSE="$(COMPOSE)" ./backup/backup-jenkins-home.sh

restore:
	@test -n "$(ARCHIVE)" || (echo "Usage: make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz" && exit 2)
	$(COMPOSE) down
	COMPOSE="$(COMPOSE)" CONFIRM_RESTORE=RESTORE ./backup/restore-jenkins-home.sh "$(ARCHIVE)"

.PHONY: prune-volumes
prune-volumes:
	docker volume prune