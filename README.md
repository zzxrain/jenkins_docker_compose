# Jenkins Docker Compose Lab

A reproducible local Jenkins CI/CD lab based on Docker Compose, Jenkins Configuration as Code, Caddy HTTPS, and static SSH build agents.

This project is designed for local development and technical validation on macOS, especially with OrbStack or Docker Desktop.

## Features

* Jenkins controller with Configuration as Code
* Caddy reverse proxy with local HTTPS
* Local Caddy root CA export for browser trust
* Static SSH build agents
* Dedicated Docker-capable Jenkins agent
* Jenkins Matrix Authorization Strategy
* SSH key based agent authentication
* Production-like SSH host key trust behavior
* Named Docker volumes for persistent data
* `tmpfs` runtime mounts for agent runtime directories
* Backup and restore scripts for Jenkins home

---

## 1. Architecture

```text
Browser / curl
    |
    | https://apps.localmac.net:8444/
    v
Caddy
    |
    | http://jenkins-controller:8080
    v
Jenkins Controller
    |
    | SSH port 22
    v
+--------------------+----------------+--------------------+
| ci-arm64-general   | ci-arm64-alm   | ci-arm64-docker    |
| General CI agent   | ALM/PLM agent  | Docker CLI agent   |
+--------------------+----------------+--------------------+
```

---

## 2. Repository Structure

```text
.
├── Makefile
├── docker-compose.yml
├── .env.example
├── .gitignore
├── caddy/
│   └── Caddyfile
├── casc/
│   └── jenkins.yaml
├── controller/
│   ├── Dockerfile
│   └── plugins.txt
├── agents/
│   ├── base/
│   │   └── Dockerfile
│   └── docker/
│       └── Dockerfile
├── backup/
│   ├── backup-jenkins-home.sh
│   └── restore-jenkins-home.sh
├── secrets/
│   └── .gitkeep
└── certs/
    └── caddy-local-root.crt
```

Generated local files such as `.env`, private keys, Caddy certificates, runtime data, and backup output should not be committed.

---

## 3. Prerequisites

Recommended environment:

* macOS
* OrbStack or Docker Desktop
* Docker Compose v2
* GNU Make
* `ssh-keygen`
* `openssl`
* `jq`
* `curl`

Check local tools:

```bash
docker version
docker compose version
make --version
openssl version
jq --version
curl --version
```

---

## 4. Local DNS

The default Jenkins URL is:

```text
https://apps.localmac.net:8444/
```

Make sure `apps.localmac.net` resolves to local loopback.

### macOS / Linux

```bash
sudo sh -c 'echo "127.0.0.1 apps.localmac.net" >> /etc/hosts'
```

### Windows

Edit this file as Administrator:

```text
C:\Windows\System32\drivers\etc\hosts
```

Add:

```text
127.0.0.1 apps.localmac.net
```

---

## 5. Environment Configuration

Initialize local environment files:

```bash
make init
```

This will:

* create `.env` from `.env.example` if missing
* generate `secrets/jenkins_agent_key`
* generate `secrets/jenkins_agent_key.pub`
* write the public key into `.env`

Typical `.env` content:

```env
TZ=Asia/Shanghai
JENKINS_URL=https://apps.localmac.net:8444/
JENKINS_ADMIN_ID=admin
JENKINS_ADMIN_PASSWORD=change-me-please
JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519 ... jenkins-agent
```

Change the default admin password before starting Jenkins:

```env
JENKINS_ADMIN_PASSWORD=your-new-password
```

Do not commit:

```text
.env
secrets/jenkins_agent_key
secrets/jenkins_agent_key.pub
```

---

## 6. Build and Start from Scratch

Recommended clean setup:

```bash
git pull
make reset-all
make init
make validate

make rebuild-controller
make rebuild-agents

docker compose up -d
```

Check service status:

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

## 7. Make Targets

Useful targets:

```bash
make help
make init
make validate
make build
make rebuild-controller
make rebuild-agents
make up
make down
make clean
make reset
make reset-images
make reset-all
make ps
make logs
make verify
make verify-volumes
make verify-agents
make verify-docker-agent
make export-caddy-root
make backup
make restore ARCHIVE=backup/output/<archive>.tar.gz
make prune-volumes
```

### Important notes for agent rebuild

The Docker-capable agent depends on the local base agent image:

```dockerfile
FROM local/jenkins-ssh-agent-base:debian-jdk21
```

Therefore the agent build order must be:

1. build `local/jenkins-ssh-agent-base:debian-jdk21`
2. build `local/jenkins-ssh-agent-docker:debian-jdk21`

Do not use `--pull` when building the Docker-capable agent, otherwise Docker may try to pull:

```text
docker.io/local/jenkins-ssh-agent-base:debian-jdk21
```

and fail with:

```text
pull access denied
```

Recommended Makefile behavior:

```makefile
rebuild-agent-base:
	$(COMPOSE) --progress=plain build --no-cache --pull ci-arm64-general

rebuild-agent-docker:
	$(COMPOSE) --progress=plain build --no-cache ci-arm64-docker

rebuild-agents: rebuild-agent-base rebuild-agent-docker
```

---

## 8. Verify Jenkins Controller

Run:

```bash
make verify
```

Expected plugin output includes:

```text
configuration-as-code.jpi
credentials.jpi
matrix-auth.jpi
ssh-credentials.jpi
ssh-slaves.jpi
```

Expected security configuration includes:

```xml
<useSecurity>true</useSecurity>
<authorizationStrategy class="hudson.security.GlobalMatrixAuthorizationStrategy">
<securityRealm class="hudson.security.HudsonPrivateSecurityRealm">
```

If you see the following, JCasC has not been applied correctly:

```xml
AuthorizationStrategy$Unsecured
SecurityRealm$None
```

Check logs:

```bash
docker compose logs --tail=300 jenkins-controller
```

---

## 9. Verify Volumes

Run:

```bash
make verify-volumes
```

Expected persistent named volumes:

```text
jenkins-docker_jenkins_home
jenkins-docker_caddy_data
jenkins-docker_caddy_config
jenkins-docker_ci_arm64_general_home
jenkins-docker_ci_arm64_alm_home
jenkins-docker_ci_arm64_docker_home
```

Agent runtime paths should be `tmpfs`, not anonymous hash volumes:

```text
/home/jenkins/.jenkins
/run
/tmp
/var/run
```

If you see hash-named volumes mounted to these paths, check `docker-compose.yml` and make sure agent common configuration contains:

```yaml
tmpfs:
  - /home/jenkins/.jenkins
  - /run
  - /tmp
  - /var/run
```

---

## 10. Verify Agent TCP Connectivity

Run:

```bash
make verify-agents
```

Expected:

```text
ci-arm64-general:22 OK
ci-arm64-alm:22 OK
ci-arm64-docker:22 OK
```

If TCP fails, check agent logs:

```bash
docker compose logs --tail=100 ci-arm64-general
docker compose logs --tail=100 ci-arm64-alm
docker compose logs --tail=100 ci-arm64-docker
```

---

## 11. SSH Host Key Trust for Jenkins Agents

The stack uses manual SSH host key verification:

```yaml
sshHostKeyVerificationStrategy:
  manuallyTrustedKeyVerificationStrategy:
    requireInitialManualTrust: true
```

This is intentional. Jenkins will not blindly trust new SSH agents.

### Expected first-time warning

When Jenkins first connects to an agent, you may see:

```text
[SSH] WARNING: The SSH key for this host is not currently trusted.
Connections will be denied until this new key is authorised.
Key exchange was not finished, connection is closed.
```

This means:

* Jenkins controller can reach the agent
* SSH port 22 is open
* `sshd` is running
* host key verification blocked the connection
* private key authentication has not started yet

This is not a network error.

### Trust the agent host key in Jenkins UI

For each agent:

```text
ci-arm64-general
ci-arm64-alm
ci-arm64-docker
```

Open Jenkins:

```text
https://apps.localmac.net:8444/
```

Then go to:

```text
Manage Jenkins
  -> Nodes
  -> <agent-name>
  -> Log
```

or:

```text
Manage Jenkins
  -> Nodes
  -> <agent-name>
  -> Launch agent
```

Look for the host key trust prompt and approve the SSH host key.

After approval, relaunch the agent.

### Why this happens again after reset

If you recreate agent containers, their SSH host keys may change.

Operations that can cause this:

```bash
make reset
make reset-all
docker compose down -v
docker compose up --force-recreate
```

When host keys change, Jenkins will ask for trust approval again.

### Local-only alternative: disable host key verification

For a local-only lab, you may replace:

```yaml
sshHostKeyVerificationStrategy:
  manuallyTrustedKeyVerificationStrategy:
    requireInitialManualTrust: true
```

with:

```yaml
sshHostKeyVerificationStrategy:
  nonVerifyingKeyVerificationStrategy: {}
```

Then restart Jenkins controller:

```bash
docker compose restart jenkins-controller
```

This is convenient for local testing, but it is not recommended for production-like validation.

---

## 12. Verify Docker-capable Agent

Run:

```bash
make verify-docker-agent
```

Expected:

```text
DOCKER_HOST=unix:///docker.sock
```

Expected commands should work:

```bash
docker version
docker buildx version
docker compose version
```

The Docker-capable agent uses:

```yaml
DOCKER_HOST: "unix:///docker.sock"
```

and mounts the host Docker socket:

```yaml
- /var/run/docker.sock:/docker.sock
```

This gives the agent high privilege over the host Docker daemon. Only trusted pipelines should run on Docker-capable labels.

---

## 13. Caddy HTTPS

Caddy exposes Jenkins over local HTTPS:

```text
https://apps.localmac.net:8444/
```

Caddy persists local CA data in:

```text
caddy_data
caddy_config
```

If these volumes are deleted, Caddy will generate a new local root CA. You must export and trust the new root certificate again.

---

## 14. Export Caddy Local Root Certificate

After the stack is running:

```bash
mkdir -p certs

docker compose cp \
  caddy:/data/caddy/pki/authorities/local/root.crt \
  ./certs/caddy-local-root.crt

openssl x509 \
  -in ./certs/caddy-local-root.crt \
  -noout \
  -subject \
  -issuer \
  -dates \
  -fingerprint \
  -sha256
```

Or use:

```bash
make export-caddy-root
```

The exported file is:

```text
certs/caddy-local-root.crt
```

Only export the certificate file. Do not export or share Caddy private keys.

---

## 15. Trust Caddy Root CA on macOS

### Option A: command line

```bash
sudo security add-trusted-cert \
  -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ./certs/caddy-local-root.crt
```

Restart Chrome, Safari, Edge, or any browser after import.

Test:

```bash
curl -Iv https://apps.localmac.net:8444/
```

Expected:

```text
SSL certificate verify ok.
HTTP/2 200
```

### Option B: Keychain Access UI

1. Open `Keychain Access`
2. Select `System`
3. Select `Certificates`
4. Import:

```text
certs/caddy-local-root.crt
```

5. Double-click the certificate
6. Expand `Trust`
7. Set `When using this certificate` to `Always Trust`
8. Close the dialog
9. Enter your macOS password
10. Restart browser

---

## 16. Trust Caddy Root CA on Windows

Copy this file to Windows:

```text
certs/caddy-local-root.crt
```

### Option A: PowerShell as Administrator

Open PowerShell as Administrator:

```powershell
Import-Certificate `
  -FilePath "C:\path\to\caddy-local-root.crt" `
  -CertStoreLocation Cert:\LocalMachine\Root
```

### Option B: MMC Local Computer Store

1. Press `Win + R`
2. Run:

```text
mmc
```

3. `File` -> `Add/Remove Snap-in`
4. Add `Certificates`
5. Choose `Computer account`
6. Choose `Local computer`
7. Go to:

```text
Trusted Root Certification Authorities
  -> Certificates
```

8. Right-click `Certificates`
9. `All Tasks` -> `Import`
10. Select `caddy-local-root.crt`
11. Finish import
12. Restart browser

### Option C: Current User Store

1. Press `Win + R`
2. Run:

```text
certmgr.msc
```

3. Go to:

```text
Trusted Root Certification Authorities
  -> Certificates
```

4. Import `caddy-local-root.crt`

For machine-wide browser trust, prefer the Local Machine store.

---

## 17. Browser Test

Open:

```text
https://apps.localmac.net:8444/
```

Expected:

* Browser does not report certificate trust errors
* Jenkins login page is displayed
* Anonymous users do not see `Manage Jenkins`
* Login works with `JENKINS_ADMIN_ID` and `JENKINS_ADMIN_PASSWORD` from `.env`

---

## 18. Backup and Restore

### Backup Jenkins Home

```bash
make backup
```

Backup archives are written to:

```text
backup/output/
```

### Restore Jenkins Home

```bash
make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz
```

Restore is destructive. Use only with a known-good backup.

---

## 19. Clean Up

### Stop services

```bash
make down
```

### Stop and remove orphan containers

```bash
make clean
```

### Remove project containers, networks, and project volumes

```bash
make reset
```

This deletes:

* Jenkins home
* Caddy local CA
* Caddy config volume
* agent workspaces

After `make reset`, you must export and trust the new Caddy root CA again.

### Remove local project images

```bash
make reset-images
```

### Full reset

```bash
make reset-all
```

### Prune unused Docker volumes

```bash
make prune-volumes
```

Do not use aggressive global prune commands unless you understand the impact on other local projects.

---

## 20. Troubleshooting

### 20.1 Jenkins is unsecured

Symptom:

```xml
AuthorizationStrategy$Unsecured
SecurityRealm$None
```

Check:

```bash
make verify
docker compose logs --tail=300 jenkins-controller
```

Common causes:

* `configuration-as-code` plugin not installed
* `CASC_JENKINS_CONFIG` not mounted
* JCasC YAML schema error
* required environment variable missing
* invalid secret path

---

### 20.2 JCasC says `sSHLauncher` is obsolete

Use:

```yaml
launcher:
  ssh:
```

Do not use:

```yaml
launcher:
  sSHLauncher:
```

Restart controller after editing JCasC:

```bash
docker compose restart jenkins-controller
```

---

### 20.3 Agent log says `/etc/environment: Permission denied`

Cause:

The `jenkins/ssh-agent` setup script is running without root privileges.

Fix:

Make sure the final runtime user in agent Dockerfiles is:

```dockerfile
USER root
```

Then rebuild agents:

```bash
make rebuild-agents
docker compose up -d --force-recreate
```

---

### 20.4 Agent log says `Missing privilege separation directory: /run/sshd`

Cause:

The agent uses `tmpfs` for `/run`. The `/run/sshd` directory must exist before `sshd` starts.

Fix:

Add an agent entrypoint wrapper in `x-agent-common`:

```yaml
entrypoint:
  - /bin/bash
  - -lc
  - |
    mkdir -p /run/sshd
    chmod 0755 /run/sshd
    exec /usr/local/bin/setup-sshd
```

Then recreate containers:

```bash
docker compose down --remove-orphans
docker compose up -d
```

---

### 20.5 Agent says SSH host key is not trusted

Symptom:

```text
[SSH] WARNING: The SSH key for this host is not currently trusted.
Connections will be denied until this new key is authorised.
```

This is expected when manual SSH host key trust is enabled.

Fix:

```text
Manage Jenkins
  -> Nodes
  -> <agent-name>
  -> Log / Launch agent
  -> Trust SSH host key
```

Then relaunch the agent.

---

### 20.6 Agent is offline but TCP 22 is OK

Run:

```bash
make verify-agents
```

If `:22 OK` but Jenkins UI still shows offline, check SSH host key trust first.

If host key is already trusted, check authentication:

```bash
docker compose exec ci-arm64-alm bash -lc '
ls -lah /home/jenkins/.ssh
cat /home/jenkins/.ssh/authorized_keys
'
```

Verify that the public key in `.env` matches:

```bash
cat secrets/jenkins_agent_key.pub
grep JENKINS_AGENT_SSH_PUBKEY .env
```

---

### 20.7 Docker agent cannot access Docker

Run:

```bash
make verify-docker-agent
```

Check:

```text
DOCKER_HOST=unix:///docker.sock
```

Check Compose socket mount:

```yaml
- /var/run/docker.sock:/docker.sock
```

Check environment:

```yaml
DOCKER_HOST: "unix:///docker.sock"
```

---

### 20.8 Anonymous hash volumes are created

Run:

```bash
make verify-volumes
```

If you see hash-named volumes mounted to agent paths such as:

```text
/home/jenkins/.jenkins
/run
/tmp
/var/run
```

Make sure `x-agent-common` contains:

```yaml
tmpfs:
  - /home/jenkins/.jenkins
  - /run
  - /tmp
  - /var/run
```

Then recreate containers:

```bash
docker compose down -v --remove-orphans
docker compose up -d
```

---

## 21. Security Notes

This stack is for local lab usage.

Important notes:

* Do not commit `.env`
* Do not commit `secrets/jenkins_agent_key`
* Do not share Caddy private keys
* Change `JENKINS_ADMIN_PASSWORD`
* Do not expose the raw Jenkins controller port beyond loopback
* The Docker-capable agent has high privilege because it can access the host Docker socket
* Do not run untrusted pipelines on the Docker-capable agent
* Keep manual SSH host key verification enabled if you want production-like behavior
* Prefer isolated build hosts or remote builders for production usage

---

## 22. Recommended Full Startup Sequence

```bash
git pull
make reset-all
make init
make validate

make rebuild-controller
make rebuild-agents

docker compose up -d

make ps
make verify
make verify-volumes
make verify-agents
make verify-docker-agent

make export-caddy-root
```

Then import:

```text
certs/caddy-local-root.crt
```

into macOS or Windows trust store.

Open:

```text
https://apps.localmac.net:8444/
```
