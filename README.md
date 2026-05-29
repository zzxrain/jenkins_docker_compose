# Jenkins Docker Compose Lab

A reproducible Jenkins local lab based on Docker Compose, Caddy HTTPS, Jenkins Configuration as Code, and static SSH build agents.

This stack is designed for local CI/CD experimentation on macOS, especially with OrbStack or Docker Desktop. It provides:

* Jenkins controller with JCasC bootstrap
* Caddy reverse proxy with local HTTPS
* Three static SSH agents:

  * `ci-arm64-general`
  * `ci-arm64-alm`
  * `ci-arm64-docker`
* Docker-capable Jenkins agent using the host Docker socket
* Local SSH key based agent authentication
* Matrix-based Jenkins authorization
* Named volumes for Jenkins, Caddy, and agent workspaces
* `tmpfs` runtime mounts for agent runtime directories to avoid anonymous Docker volumes

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
    | SSH
    | port 22
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

Runtime files such as `.env`, private keys, generated certificates, data directories, and backup output archives should not be committed.

---

## 3. Prerequisites

Recommended local environment:

* macOS
* OrbStack or Docker Desktop
* Docker Compose v2
* `make`
* `ssh-keygen`
* `openssl`
* `jq`
* `curl`

Check versions:

```bash
docker version
docker compose version
make --version
openssl version
jq --version
```

---

## 4. Local DNS

This stack uses:

```text
apps.localmac.net
```

The domain should resolve to loopback:

```bash
curl -Iv https://apps.localmac.net:8444/
```

If DNS does not resolve correctly, add a hosts entry.

### macOS / Linux

```bash
sudo sh -c 'echo "127.0.0.1 apps.localmac.net" >> /etc/hosts'
```

### Windows

Open Notepad as Administrator and edit:

```text
C:\Windows\System32\drivers\etc\hosts
```

Add:

```text
127.0.0.1 apps.localmac.net
```

---

## 5. Configuration

### 5.1 `.env`

Create `.env` from `.env.example`:

```bash
make init
```

The generated `.env` contains values similar to:

```env
TZ=Asia/Shanghai
JENKINS_URL=https://apps.localmac.net:8444/
JENKINS_ADMIN_ID=admin
JENKINS_ADMIN_PASSWORD=change-me-please
JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519 ... jenkins-agent
```

Change the admin password before using the stack:

```env
JENKINS_ADMIN_PASSWORD=your-new-password
```

The private key is generated locally at:

```text
secrets/jenkins_agent_key
```

The public key is written into:

```env
JENKINS_AGENT_SSH_PUBKEY=...
```

Do not commit `.env` or private keys.

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

### Important targets

#### Initialize local files

```bash
make init
```

Creates `.env`, generates `secrets/jenkins_agent_key`, and updates `JENKINS_AGENT_SSH_PUBKEY`.

#### Validate Compose configuration

```bash
make validate
```

#### Rebuild Jenkins controller

```bash
make rebuild-controller
```

#### Rebuild agents

```bash
make rebuild-agents
```

The agent rebuild is intentionally split internally:

1. Build `local/jenkins-ssh-agent-base:debian-jdk21`
2. Build `local/jenkins-ssh-agent-docker:debian-jdk21`

The Docker-capable agent is based on the locally built base image. Do not use `--pull` when building the Docker-capable agent, otherwise Docker may try to pull `docker.io/local/jenkins-ssh-agent-base:debian-jdk21`.

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

---

## 9. Verify Agent Connectivity

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

If TCP is OK but agents are still offline in Jenkins UI, check SSH host key trust.

This stack uses manual SSH host key trust:

```yaml
manuallyTrustedKeyVerificationStrategy:
  requireInitialManualTrust: true
```

Go to Jenkins UI:

```text
Manage Jenkins
  -> Nodes
  -> <agent>
  -> Log / Launch agent
```

Approve or trust the presented SSH host key.

---

## 10. Verify Docker-capable Agent

Run:

```bash
make verify-docker-agent
```

Expected:

```text
DOCKER_HOST=unix:///docker.sock
```

And successful output from:

```bash
docker version
docker buildx version
docker compose version
```

The Docker-capable agent mounts the host Docker socket:

```yaml
- /var/run/docker.sock:/docker.sock
```

This gives the agent high privilege over the host Docker daemon. Only trusted pipelines should run on Docker-capable labels.

---

## 11. Verify Volumes

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

The following paths should not be hash-named anonymous Docker volumes:

```text
/home/jenkins/.jenkins
/run
/tmp
/var/run
```

---

## 12. Caddy HTTPS and Local Root CA

Caddy uses an internal local CA for HTTPS.

The Jenkins external URL is:

```text
https://apps.localmac.net:8444/
```

Caddy persists its local CA and runtime configuration in named volumes:

```text
caddy_data
caddy_config
```

If you delete these volumes, Caddy will generate a new local root CA. You must export and trust the new root certificate again.

---

## 13. Export Caddy Local Root Certificate

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

## 14. Trust Caddy Root CA on macOS

### Option A: command line

```bash
sudo security add-trusted-cert \
  -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ./certs/caddy-local-root.crt
```

Restart Chrome, Safari, or other browsers after import.

Then test:

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
4. Import `certs/caddy-local-root.crt`
5. Double-click the certificate
6. Expand `Trust`
7. Set `When using this certificate` to `Always Trust`
8. Close the dialog and enter your macOS password
9. Restart browser

---

## 15. Trust Caddy Root CA on Windows

Copy this file to Windows:

```text
certs/caddy-local-root.crt
```

### Option A: PowerShell as Administrator

```powershell
Import-Certificate `
  -FilePath "C:\path\to\caddy-local-root.crt" `
  -CertStoreLocation Cert:\LocalMachine\Root
```

### Option B: Microsoft Management Console

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

### Option C: certmgr.msc for current user

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

## 16. Browser Test

Open:

```text
https://apps.localmac.net:8444/
```

Expected:

* Browser does not report certificate trust errors
* Jenkins login page is displayed
* Anonymous users do not see `Manage Jenkins`
* Login with `JENKINS_ADMIN_ID` and `JENKINS_ADMIN_PASSWORD` from `.env`

---

## 17. Backup and Restore

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

## 18. Clean Up

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

* Jenkins Home
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

## 19. Troubleshooting

### 19.1 Jenkins is unsecured

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

### 19.2 JCasC says `sSHLauncher` is obsolete

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

### 19.3 Agent log says `Missing privilege separation directory: /run/sshd`

Cause:

The agent uses `tmpfs` for `/run`. The directory `/run/sshd` must exist before `sshd` starts.

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

### 19.4 Agent is offline but TCP 22 is OK

Run:

```bash
make verify-agents
```

If `:22 OK` but Jenkins UI still shows offline, check SSH host key trust:

```text
Manage Jenkins
  -> Nodes
  -> <agent>
  -> Log / Launch agent
  -> Trust SSH host key
```

This is expected when manual host key trust is enabled.

---

### 19.5 Docker agent cannot access Docker

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

### 19.6 Anonymous hash volumes are created

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

## 20. Security Notes

This stack is for local lab usage.

Important security notes:

* Do not commit `.env`
* Do not commit `secrets/jenkins_agent_key`
* Do not share Caddy private keys
* Change `JENKINS_ADMIN_PASSWORD`
* Do not expose the raw Jenkins controller port beyond loopback
* The Docker-capable agent has high privilege because it can access the host Docker socket
* Do not run untrusted pipelines on the Docker-capable agent
* Prefer isolated build hosts or remote builders for production usage

---

## 21. Recommended Full Startup Sequence

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

Then import `certs/caddy-local-root.crt` into macOS or Windows trust store and open:

```text
https://apps.localmac.net:8444/
```
