# Jenkins Docker Compose CI/CD Lab

This repository provides a local Jenkins CI/CD lab based on Docker Compose. It is designed for learning CI/CD, simulating an enterprise-like Jenkins architecture, and preparing future integrations with PTC Windchill PLM and PTC Codebeamer ALM.

The stack includes:

* A Jenkins Controller
* Static SSH-based Jenkins agents
* A dedicated Docker-capable build agent
* Caddy as a local HTTPS reverse proxy
* Jenkins Configuration as Code
* Docker named volumes for persistent data
* Backup and restore scripts for Jenkins Home

This repository is intended for a local lab or production-like architecture simulation. It is not a drop-in production Jenkins HA architecture.

---

## Architecture

```text
Browser
  |
  | HTTPS: https://apps.localmac.net:8444/
  v
Caddy Reverse Proxy
  |
  | HTTP: jenkins-controller:8080
  v
Jenkins Controller
  |
  | SSH
  +--> ci-arm64-general
  |
  | SSH
  +--> ci-arm64-alm
  |
  | SSH
  +--> ci-arm64-docker
          |
          +--> /var/run/docker.sock
```

### Main components

| Component            | Purpose                                                                                                              |
| -------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `jenkins-controller` | Jenkins Controller. It manages configuration, credentials, scheduling and orchestration. It does not run build jobs. |
| `jenkins-caddy`      | Local HTTPS reverse proxy for Jenkins.                                                                               |
| `ci-arm64-general`   | General-purpose SSH agent for normal CI tasks.                                                                       |
| `ci-arm64-alm`       | Dedicated SSH agent for ALM/PLM automation tasks such as Windchill and Codebeamer integration.                       |
| `ci-arm64-docker`    | Dedicated SSH agent with Docker CLI, Docker Compose plugin and Buildx support.                                       |
| `jenkins_home`       | Docker named volume for Jenkins Controller state.                                                                    |
| `caddy_data`         | Docker named volume for Caddy local CA and runtime data.                                                             |

---

## Design Goals

This project is intentionally structured to be more enterprise-like than a single all-in-one Jenkins container.

Key design decisions:

* The Jenkins Controller has `numExecutors: 0`.
* Builds must run on agents, not on the controller.
* Agents are separated by responsibility.
* Docker build capability is isolated to a dedicated high-trust agent.
* Jenkins baseline configuration is managed through JCasC.
* Jenkins raw HTTP port is bound to `127.0.0.1` only.
* External browser access should go through Caddy HTTPS.
* Jenkins agent SSH private key is passed through Docker secrets, not environment variables.
* SSH host key verification uses a production-like manual trust model.
* Jenkins Home can be backed up and restored through scripts.

---

## Repository Layout

```text
jenkins_docker_compose/
├─ .env.example
├─ .gitignore
├─ Makefile
├─ README.md
├─ docker-compose.yml
├─ controller/
│  ├─ Dockerfile
│  └─ plugins.txt
├─ agents/
│  ├─ base/
│  │  └─ Dockerfile
│  └─ docker/
│     └─ Dockerfile
├─ casc/
│  └─ jenkins.yaml
├─ caddy/
│  └─ Caddyfile
├─ backup/
│  ├─ backup-jenkins-home.sh
│  └─ restore-jenkins-home.sh
└─ secrets/
   └─ .gitkeep
```

The `secrets/jenkins_agent_key` file is generated locally by `make init` and must never be committed.

---

## Prerequisites

The following prerequisites are expected on the host machine.

### Required tools

* macOS with Docker Desktop or OrbStack
* Docker Compose v2
* GNU Make
* OpenSSH tools, including `ssh-keygen`
* `jq`

### Recommended macOS setup

Install `jq` with Homebrew:

```bash
brew install jq
```

Check basic tools:

```bash
docker version
docker compose version
make --version
ssh-keygen -h
jq --version
```

The `ssh-keygen -h` command may start key generation on some systems. Press `Ctrl+C` if that happens. It is only a quick availability check.

---

## Ports

| Host Port | Container                 | Purpose                                                  |
| --------: | ------------------------- | -------------------------------------------------------- |
|    `8444` | `jenkins-caddy:443`       | Main HTTPS access point                                  |
|    `8089` | `jenkins-controller:8080` | Local-only raw Jenkins HTTP access, bound to `127.0.0.1` |

Primary access URL:

```text
https://apps.localmac.net:8444/
```

Local troubleshooting URL:

```text
http://127.0.0.1:8089/
```

The raw Jenkins HTTP endpoint is bound to loopback only. External access should go through Caddy.

---

## First-Time Deployment

Follow this section step by step for the initial deployment.

### 1. Clone the repository

```bash
cd ~/Documents/Technology/DevOps
git clone https://github.com/zzxrain/jenkins_docker_compose.git
cd jenkins_docker_compose
```

Check the repository files:

```bash
ls -la
```

Expected important files:

```text
docker-compose.yml
Makefile
.env.example
controller/
agents/
casc/
caddy/
backup/
secrets/
```

---

### 2. Initialize local configuration and SSH key

Run:

```bash
make init
```

This command does the following:

* Creates `.env` from `.env.example` if `.env` does not already exist.
* Creates the `secrets/` directory if needed.
* Generates `secrets/jenkins_agent_key`.
* Generates `secrets/jenkins_agent_key.pub`.
* Updates `JENKINS_AGENT_SSH_PUBKEY` in `.env` if it still contains the placeholder value.
* Sets the private key permission to `600`.

Check generated files:

```bash
ls -la .env secrets/
```

Expected:

```text
.env
secrets/jenkins_agent_key
secrets/jenkins_agent_key.pub
```

Do not commit `.env` or `secrets/jenkins_agent_key`.

---

### 3. Edit `.env`

Open `.env`:

```bash
vim .env
```

A typical `.env` should look like this:

```env
TZ=Asia/Shanghai
JENKINS_URL=https://apps.localmac.net:8444/
JENKINS_ADMIN_ID=admin
JENKINS_ADMIN_PASSWORD=change-me-please

JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519 ... jenkins-agent
```

Change at least:

```env
JENKINS_ADMIN_PASSWORD=change-me-please
```

Use a stronger password.

Example:

```env
JENKINS_ADMIN_PASSWORD=your-strong-local-password
```

Keep this URL for the default local HTTPS setup:

```env
JENKINS_URL=https://apps.localmac.net:8444/
```

---

### 4. Validate Docker Compose configuration

Run:

```bash
make validate
```

This validates the Compose file after environment variable interpolation.

If validation fails, check:

```bash
cat .env
ls -la secrets/
docker compose config
```

Common causes:

* `.env` does not exist.
* `JENKINS_ADMIN_ID` is missing.
* `JENKINS_ADMIN_PASSWORD` is missing.
* `JENKINS_AGENT_SSH_PUBKEY` is missing.
* `secrets/jenkins_agent_key` does not exist.

Run `make init` again if local files are missing.

---

### 5. Build and start the stack

Run:

```bash
make up
```

This command will:

* Build the Jenkins Controller image.
* Build the base SSH agent image.
* Build the Docker-capable SSH agent image.
* Start Jenkins Controller.
* Start Caddy.
* Start all static SSH agents.

Watch the logs:

```bash
make logs
```

You can also check container status:

```bash
make ps
```

Expected services:

```text
jenkins-controller
jenkins-caddy
ci-arm64-general
ci-arm64-alm
ci-arm64-docker
```

---

### 6. Access Jenkins

Open:

```text
https://apps.localmac.net:8444/
```

Log in with the values from `.env`:

```text
JENKINS_ADMIN_ID
JENKINS_ADMIN_PASSWORD
```

For troubleshooting only, you can also access:

```text
http://127.0.0.1:8089/
```

---

## Local HTTPS and Caddy CA Trust

Caddy uses `tls internal` for local HTTPS simulation.

This means Caddy generates a local CA and a certificate for:

```text
jenkins.localhost
```

Your browser may warn that the certificate is not trusted.

For a local lab, you can either:

* Proceed through the browser warning, or
* Trust Caddy's local root CA in macOS Keychain.

To locate the Caddy local root certificate:

```bash
docker exec -it jenkins-caddy sh
find /data -name root.crt -o -name "*.crt"
exit
```

A typical path is:

```text
/data/caddy/pki/authorities/local/root.crt
```

Copy it to the repository:

```bash
docker cp jenkins-caddy:/data/caddy/pki/authorities/local/root.crt ./caddy/caddy-local-root.crt
```

Trust it in macOS System Keychain:

```bash
sudo security add-trusted-cert \
  -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ./caddy/caddy-local-root.crt
```

Then restart your browser and open:

```text
https://apps.localmac.net:8444/
```

---

## First-Time SSH Agent Trust

This lab uses `manuallyTrustedKeyVerificationStrategy` for SSH agent host key verification.

That means Jenkins will not blindly trust SSH agents on the first connection. An administrator must review and approve each agent's SSH host key.

After `make up`:

1. Open `https://apps.localmac.net:8444/`
2. Log in as the Jenkins administrator.
3. Go to **Manage Jenkins → Nodes**.
4. Open each SSH agent:

   * `ci-arm64-general`
   * `ci-arm64-alm`
   * `ci-arm64-docker`
5. Review and approve the presented SSH host key.
6. Wait until each agent becomes online.

This is expected behavior.

If an agent container is recreated and its SSH host key changes, Jenkins may require approval again. This is expected for a production-like trust model.

---

## Post-Start Verification

### 1. Check containers

```bash
make ps
```

Expected result:

* `jenkins-controller` is running.
* `jenkins-caddy` is running.
* `ci-arm64-general` is running.
* `ci-arm64-alm` is running.
* `ci-arm64-docker` is running.

### 2. Check logs

```bash
make logs
```

Look for serious errors such as:

```text
SEVERE
ConfiguratorException
CannotResolveClassException
Failed Loading plugin
```

### 3. Check Jenkins nodes

In Jenkins UI:

```text
Manage Jenkins → Nodes
```

Expected nodes:

```text
Built-In Node
ci-arm64-general
ci-arm64-alm
ci-arm64-docker
```

Expected controller behavior:

```text
Built-In Node executors = 0
```

The controller should not run builds.

### 4. Verify agent labels

Expected labels:

| Agent              | Labels                                    |
| ------------------ | ----------------------------------------- |
| `ci-arm64-general` | `ci arm64 linux general`                  |
| `ci-arm64-alm`     | `ci arm64 linux alm codebeamer windchill` |
| `ci-arm64-docker`  | `ci arm64 linux docker buildx`            |

---

## Recommended Test Pipeline

Create a temporary Jenkins Pipeline job to validate the agents.

In Jenkins:

```text
New Item → Pipeline
```

Use this script:

```groovy
pipeline {
    agent none

    options {
        timestamps()
    }

    stages {
        stage('General Agent') {
            agent { label 'linux && arm64 && general' }
            steps {
                sh '''
                    echo "NODE_NAME=$NODE_NAME"
                    hostname
                    whoami
                    java -version
                    git --version
                    jq --version
                '''
            }
        }

        stage('ALM Agent') {
            agent { label 'linux && arm64 && alm' }
            steps {
                sh '''
                    echo "NODE_NAME=$NODE_NAME"
                    hostname
                    whoami
                    curl --version
                    jq --version
                '''
            }
        }

        stage('Docker Agent') {
            agent { label 'linux && arm64 && docker' }
            steps {
                sh '''
                    echo "NODE_NAME=$NODE_NAME"
                    hostname
                    whoami
                    docker version
                    docker compose version
                    docker buildx version
                '''
            }
        }
    }
}
```

The Docker stage should run only on `ci-arm64-docker`.

---

## Daily Operations

### Start or update the stack

```bash
make up
```

### Stop the stack

```bash
make down
```

### View logs

```bash
make logs
```

### Show Compose service status

```bash
make ps
```

### Validate Compose configuration

```bash
make validate
```

### Rebuild images

```bash
make build
```

### Remove stopped containers and orphaned services

```bash
make clean
```

`make clean` does not remove named volumes.

---

## Backup

The backup script creates a tar archive of the `jenkins_home` named volume.

Run:

```bash
make backup
```

Backups are written to:

```text
backup/output/
```

Example:

```text
backup/output/jenkins_home_20260529-153000.tar.gz
```

The script resolves the actual Compose volume name automatically using:

```text
docker compose config --format json
```

and `jq`.

### Backup before upgrades

Before changing Jenkins version, plugin versions, JCasC structure, or agent images, run:

```bash
make backup
```

---

## Restore

To restore a previous Jenkins Home backup:

```bash
make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz
```

Example:

```bash
make restore ARCHIVE=backup/output/jenkins_home_20260529-153000.tar.gz
```

The restore process:

1. Stops the Compose stack.
2. Clears the target `jenkins_home` volume.
3. Extracts the selected backup archive into the volume.

Restore is destructive. Always verify the backup archive path before running it.

---

## Upgrade Procedure

Use this procedure when upgrading Jenkins LTS, plugin versions, or agent images.

### 1. Back up Jenkins Home

```bash
make backup
```

### 2. Modify version-controlled files

Typical files:

```text
controller/Dockerfile
controller/plugins.txt
agents/base/Dockerfile
agents/docker/Dockerfile
docker-compose.yml
casc/jenkins.yaml
```

### 3. Validate configuration

```bash
make validate
```

### 4. Build images

```bash
make build
```

### 5. Start the stack

```bash
make up
```

### 6. Check logs

```bash
make logs
```

### 7. Verify Jenkins

Check:

* Jenkins login
* JCasC loading
* Plugin loading
* Agent connectivity
* Pipeline execution
* Docker build capability on `ci-arm64-docker`

---

## Rollback Procedure

If an upgrade fails:

### 1. Stop the stack

```bash
make down
```

### 2. Revert version-controlled files

Use Git to revert changes to files such as:

```text
controller/Dockerfile
controller/plugins.txt
casc/jenkins.yaml
docker-compose.yml
```

### 3. Restore Jenkins Home

```bash
make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz
```

### 4. Start the stack

```bash
make up
```

### 5. Check logs

```bash
make logs
```

---

## Security Model

### Controller isolation

The Jenkins Controller is configured with:

```text
numExecutors: 0
```

This means build jobs should not run on the controller.

Builds should run on dedicated SSH agents.

### Permission model

JCasC configures a matrix-based authorization model.

The bootstrap administrator receives:

```text
Overall/Administer
```

Authenticated users receive read-only access by default.

For a real team setup, create separate folders and apply folder-level or job-level permissions.

Recommended folder structure:

```text
/ci/general
/ci/alm
/ci/docker
```

The Docker folder should be restricted to trusted maintainers.

### Credential handling

Do not commit:

```text
.env
secrets/jenkins_agent_key
backup/output/
```

The Jenkins agent private key is mounted into the controller through Docker secrets and then registered as a Jenkins SSH credential through JCasC.

For enterprise production, replace local secrets with one of the following:

* HashiCorp Vault
* Enterprise secret manager
* Cloud KMS / secret service
* Jenkins Credentials Provider integration

---

## SSH Agent Host Key Verification

This lab uses:

```text
manuallyTrustedKeyVerificationStrategy
```

This means:

* Jenkins will not blindly trust a new SSH agent.
* An administrator must approve the SSH host key on first connection.
* If the SSH host key changes, Jenkins may block the connection again.
* This is more production-like than disabling verification.

This is still not the strictest production model.

For stricter enterprise-style deployments, consider:

```text
knownHostsFileKeyVerificationStrategy
```

That approach requires maintaining a controlled `known_hosts` file and making agent SSH host keys stable.

---

## Docker Socket Risk and Alternatives

The `ci-arm64-docker` agent mounts:

```text
/var/run/docker.sock
```

This allows Jenkins pipelines on that agent to run Docker CLI, Docker Compose and Buildx commands.

This is convenient for a local CI/CD lab, but it is a high-trust configuration.

A job with access to this socket can control the host Docker daemon, including:

* Creating containers
* Removing containers
* Creating privileged containers
* Mounting host paths
* Reading or modifying Docker volumes
* Interacting with Docker images
* Creating or modifying Docker networks
* Affecting other services using the same Docker daemon

Treat this agent as a privileged build worker.

### Current lab policy

* Only trusted Jenkinsfiles should use the `docker` or `buildx` labels.
* Do not run unreviewed pull request builds on `ci-arm64-docker`.
* Keep general ALM/PLM API jobs on `ci-arm64-alm`.
* Keep the Jenkins Controller free of Docker socket access.
* Treat credentials used by Docker-capable jobs as higher risk.
* Do not allow arbitrary user-provided scripts to run on the Docker-capable agent.

### Acceptable for this repository

For a local macOS / OrbStack learning environment, this design is acceptable because it is simple, fast and practical.

It should not be copied directly into a production Jenkins architecture without additional isolation and governance.

### Production-oriented alternatives

For a more production-like or enterprise setup, consider the following alternatives.

#### Option 1: Remote BuildKit builder

Use a dedicated BuildKit daemon as a remote builder.

```text
Jenkins Docker Agent
  → docker buildx
  → Remote BuildKit daemon
  → Container registry
```

Benefits:

* The Jenkins agent does not need direct access to the host Docker daemon.
* Build capacity can be isolated and scaled.
* Better fit for enterprise build infrastructure.

#### Option 2: Dedicated isolated Docker build host

Run Docker builds on a dedicated Linux build host.

```text
Jenkins Controller
  → SSH Agent on isolated build host
  → Local Docker daemon on that build host
```

Benefits:

* Docker risk is isolated away from the Jenkins Controller host.
* Easier to rebuild or rotate the build host.
* Simpler than Kubernetes for small environments.

#### Option 3: Kubernetes dynamic agents

Use Kubernetes-based Jenkins agents with tools such as:

* Kaniko
* BuildKit
* Buildah

Benefits:

* Ephemeral build agents
* Better isolation through Kubernetes namespaces, service accounts and RBAC
* Closer to cloud-native CI/CD patterns

#### Option 4: Rootless Podman / Buildah

For Red Hat-oriented environments, use rootless Podman or Buildah on a dedicated Linux worker.

Benefits:

* Better alignment with RHEL / OpenShift ecosystems
* Avoids direct access to a rootful Docker daemon
* More production-friendly for regulated Linux environments

#### Option 5: Managed build service

Use a managed builder such as Docker Build Cloud or an enterprise equivalent.

Benefits:

* Less local infrastructure to maintain
* Potentially better caching and scalability
* Reduced local Docker daemon exposure

---

## Windchill and Codebeamer Integration Guidance

Use `ci-arm64-alm` for ALM/PLM automation.

Recommended label:

```groovy
agent { label 'linux && arm64 && alm' }
```

Recommended practices:

* Store Windchill credentials in Jenkins Credentials.
* Store Codebeamer credentials in Jenkins Credentials.
* Do not hard-code API tokens in Jenkinsfiles.
* Use `withCredentials` for secret binding.
* Add timeouts to all API calls.
* Add retry logic only for safe and idempotent operations.
* Log external object IDs, tracker item IDs, change notice numbers and artifact checksums.
* Keep ALM/PLM API scripts separate from Docker build scripts.
* Consider moving reusable logic into a Jenkins Shared Library or a dedicated CLI.

Example stages for future pipelines:

```text
Validate parameters
Checkout source
Build or package artifact
Run tests
Publish reports
Call Codebeamer API
Call Windchill API
Update traceability records
Archive artifacts
```

---

## Agent Labeling Strategy

| Label        | Meaning                       |
| ------------ | ----------------------------- |
| `linux`      | Linux-based agent             |
| `arm64`      | ARM64 architecture            |
| `general`    | General CI workload           |
| `alm`        | ALM/PLM automation workload   |
| `codebeamer` | Codebeamer-related automation |
| `windchill`  | Windchill-related automation  |
| `docker`     | Docker CLI capable agent      |
| `buildx`     | Docker Buildx capable agent   |

Recommended usage:

```groovy
agent { label 'linux && arm64 && general' }
```

```groovy
agent { label 'linux && arm64 && alm' }
```

```groovy
agent { label 'linux && arm64 && docker' }
```

Do not use the Docker labels for untrusted or general-purpose jobs.

---

## Troubleshooting

### Compose validation fails

Run:

```bash
docker compose config
```

Check whether `.env` exists:

```bash
ls -la .env
```

Check whether the private key exists:

```bash
ls -la secrets/jenkins_agent_key
```

Run initialization again if needed:

```bash
make init
```

---

### Jenkins does not start

Check logs:

```bash
make logs
```

Or:

```bash
docker logs -f jenkins-controller
```

Look for:

```text
Failed Loading plugin
ConfiguratorException
CannotResolveClassException
```

---

### Jenkins cannot load JCasC

Check:

```bash
docker logs jenkins-controller | grep -i casc
```

Validate the YAML file:

```bash
cat casc/jenkins.yaml
```

Check whether required environment variables are present:

```bash
cat .env
```

---

### Agents are offline

This may be expected on first startup because host key trust is required.

Check:

```text
Manage Jenkins → Nodes
```

Open each agent and approve the SSH host key if prompted.

Also check agent containers:

```bash
docker ps | grep ci-arm64
```

Check whether the public key was injected:

```bash
grep JENKINS_AGENT_SSH_PUBKEY .env
```

Check whether the private key exists:

```bash
ls -la secrets/jenkins_agent_key
```

---

### Docker commands fail on `ci-arm64-docker`

Open a shell:

```bash
docker exec -it ci-arm64-docker bash
```

Check Docker access:

```bash
docker version
docker compose version
docker buildx version
```

If you see permission errors against `/var/run/docker.sock`, check the Docker socket permissions on the host and the effective user inside the agent.

---

### Browser shows HTTPS certificate warning

This is expected when using Caddy internal CA.

Options:

* Proceed through the browser warning for local testing.
* Import Caddy's local root CA into macOS Keychain.
* Use a real domain and certificate for a more production-like setup.

---

### Backup fails because `jq` is missing

Install `jq`:

```bash
brew install jq
```

Then retry:

```bash
make backup
```

---

## Cleanup

Stop the stack:

```bash
make down
```

Remove stopped containers and orphans:

```bash
make clean
```

To remove volumes, use Docker commands manually. Be careful: removing volumes deletes Jenkins state.

List volumes:

```bash
docker volume ls | grep jenkins
```

Remove a specific volume only if you are sure:

```bash
docker volume rm <volume-name>
```

---

## Important Files

| File                             | Purpose                                                 |
| -------------------------------- | ------------------------------------------------------- |
| `docker-compose.yml`             | Defines Jenkins Controller, Caddy and static SSH agents |
| `controller/Dockerfile`          | Builds the Jenkins Controller image                     |
| `controller/plugins.txt`         | Pins Jenkins plugin versions                            |
| `agents/base/Dockerfile`         | Builds the base SSH agent image                         |
| `agents/docker/Dockerfile`       | Builds the Docker-capable SSH agent image               |
| `casc/jenkins.yaml`              | Jenkins Configuration as Code                           |
| `caddy/Caddyfile`                | Local HTTPS reverse proxy configuration                 |
| `Makefile`                       | Common operational commands                             |
| `backup/backup-jenkins-home.sh`  | Jenkins Home backup script                              |
| `backup/restore-jenkins-home.sh` | Jenkins Home restore script                             |
| `.env.example`                   | Template for local environment variables                |

---

## Known Limitations

* This is a single-controller lab environment, not a high-availability Jenkins architecture.
* Caddy uses a local internal CA by default, not a public or enterprise CA.
* Docker socket access is intentionally available only on `ci-arm64-docker`, but it remains high risk.
* SSH host key verification is production-like but not the strictest possible model.
* This repository is optimized for local learning and architecture simulation, not direct production deployment.

---

## Recommended Next Improvements

Potential future enhancements:

* Add `examples/pipelines/check-agents.Jenkinsfile`
* Add `examples/pipelines/codebeamer-api-check.Jenkinsfile`
* Add `examples/pipelines/windchill-api-check.Jenkinsfile`
* Add `examples/pipelines/docker-build.Jenkinsfile`
* Add a remote BuildKit example
* Add a `known_hosts` based SSH host key verification profile
* Add Jenkins Shared Library examples for Windchill and Codebeamer integration
* Add monitoring examples with Prometheus and Grafana
* Add log aggregation examples with Loki or ELK

---

## Usage Summary

For first-time deployment:

```bash
make init
vim .env
make validate
make up
make logs
```

For daily startup:

```bash
make up
```

For shutdown:

```bash
make down
```

For backup:

```bash
make backup
```

For restore:

```bash
make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz
```

Primary access URL:

```text
https://apps.localmac.net:8444/
```
