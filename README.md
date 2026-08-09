# Jenkins Docker Compose Lab

A reproducible local Jenkins CI/CD lab based on Docker Compose, Jenkins Configuration as Code, Caddy HTTPS, and static SSH build agents.

This project is designed for local development and technical validation on macOS, especially with OrbStack or Docker Desktop.

## Features

* Jenkins controller with Configuration as Code
* Caddy reverse proxy with local HTTPS
* Local Caddy root CA export for browser trust
* Static SSH build agents
* Dedicated Docker-capable Jenkins agent
* ACL-scoped Docker socket access for the Jenkins Pipeline user
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

Generated local files such as `.env`, private keys, Caddy certificates, and
runtime data should not be committed. Jenkins Home archives are written outside
the repository by default.

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
make restore ARCHIVE="$HOME/DevTools/Backup/jenkins-docker/<archive>.tar.gz"
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

The verification target deliberately runs as the `jenkins` user, matching the
identity used by real SSH/remoting Pipeline steps. A root-only check can hide
socket permission failures.

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

OrbStack and Docker Desktop may expose the mounted socket as `root:root` with
mode `0660`. The Docker agent image includes `setfacl`, and its service-specific
entrypoint grants access only to the `jenkins` user before starting `sshd`:

```bash
setfacl -m u:jenkins:rw /docker.sock
```

This avoids adding `jenkins` to the container's broad `root` group. It does not
reduce the inherent privilege of Docker daemon access: any process that can use
the socket has root-equivalent control of the Docker host.

This gives the agent high privilege over the host Docker daemon. Only trusted pipelines should run on Docker-capable labels.

---

## 13. Caddy HTTPS

Caddy exposes Jenkins over local HTTPS:

```text
https://apps.localmac.net:8444/
```

This local development stack deliberately configures different lifetimes for
each level of Caddy's internal certificate chain:

| Certificate | Configured lifetime | Renewal behavior |
| --- | ---: | --- |
| Local root CA | Caddy default: 3600 days (about 10 years) | Persisted in `caddy_data`; this is the certificate trusted by the host OS |
| Intermediate CA | 30 days | Managed and rotated automatically by Caddy while it is running |
| `apps.localmac.net` leaf certificate | 7 days | Enters Caddy's normal renewal window when approximately one third of its lifetime remains |

The 7-day leaf and 30-day intermediate lifetimes are intentional for this
personal development environment, where the Compose stack may be stopped for
several days. They reduce avoidable expiry warnings compared with Caddy's
12-hour/7-day defaults without turning the site certificate into a long-lived
10-year credential. The leaf lifetime must always be shorter than the
intermediate lifetime.

Caddy cannot renew certificates while its container is stopped. When the stack
starts again, Caddy should issue or renew certificates from the persisted local
CA. Caddy installs the persisted local root into its container trust store, and
the Compose healthcheck performs a real HTTPS request through that trust store.
An expired or incomplete served chain therefore makes the `caddy` service
unhealthy instead of merely checking that the binary exists.

Caddy persists local CA data in:

```text
caddy_data
caddy_config
```

If these volumes are deleted, Caddy will generate a new local root CA. You must export and trust the new root certificate again.

Do not use `docker compose down -v` unless you intentionally want to delete the
local CA and all other project volumes. Ordinary `docker compose stop`,
`docker compose down`, `docker compose restart caddy`, and container recreation
retain the named volumes.

Inspect the certificate currently served to clients with:

```bash
openssl s_client \
  -connect apps.localmac.net:8444 \
  -servername apps.localmac.net </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

If Caddy was stopped past the certificate lifetime and does not recover
automatically, restart only that service and inspect its logs:

```bash
docker compose restart caddy
docker compose logs --tail=100 caddy
curl -Iv https://apps.localmac.net:8444/
```

### Certificate lifetime change performed on 2026-08-09

The configuration was changed from Caddy's default 12-hour leaf and 7-day
intermediate lifetimes to a 7-day leaf and 30-day intermediate. The Caddyfile,
Compose model, and adapted JSON configuration were validated before the `caddy`
container was recreated with its existing named volumes.

Validation after the recreation showed:

* `https://apps.localmac.net:8444/login` returned HTTP 200.
* The real HTTPS healthcheck passed and the container reached `healthy`.
* The local root fingerprint remained
  `47:86:50:E7:54:28:BC:BD:F6:80:38:9B:92:AF:3E:7D:C2:07:43:07:3F:7E:B6:B2:DB:22:82:A3:BB:E1:39:43`
  and its expiry remained 2036-04-06.
* Caddy's adapted runtime configuration contained a 7-day leaf lifetime and a
  30-day intermediate lifetime.
* Caddy initially reused the already-issued valid 12-hour leaf and 7-day
  intermediate. Caddy does not replace a valid stored certificate merely
  because its configured lifetime changes; the configured 7-day/30-day values
  take effect when those certificates are next automatically issued or rotated.

No certificate volume was deleted, no new root CA was generated, and no host
trust-store update was required.

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

For an upgrade or rollback point, create a cold backup. Stop the stack first so
that job records, queues, plugin files, and configuration are mutually
consistent:

```bash
docker compose down
make backup
```

Backup archives are written outside the Git repository by default:

```text
$HOME/DevTools/Backup/jenkins-docker/
```

On the macOS development host used for this project, this resolves to:

```text
/Users/pandahorn/DevTools/Backup/jenkins-docker/
```

Override the destination for a one-off backup when needed:

```bash
make backup BACKUP_DIR=/absolute/path/to/another/backup-directory
```

The backup script normalizes both absolute and relative `BACKUP_DIR` values
before mounting the destination into its temporary archive container. Large
archives therefore never need to be created inside the Git working tree.

Validate the archive before changing the controller version:

```bash
gzip -t "$HOME/DevTools/Backup/jenkins-docker/jenkins_home_YYYYmmdd-HHMMSS.tar.gz"
tar tzf "$HOME/DevTools/Backup/jenkins-docker/jenkins_home_YYYYmmdd-HHMMSS.tar.gz" >/dev/null
shasum -a 256 "$HOME/DevTools/Backup/jenkins-docker/jenkins_home_YYYYmmdd-HHMMSS.tar.gz"
```

### Restore Jenkins Home

```bash
make restore \
  ARCHIVE="$HOME/DevTools/Backup/jenkins-docker/jenkins_home_YYYYmmdd-HHMMSS.tar.gz"
```

The restore script accepts archives outside the repository and mounts only the
selected archive's parent directory read-only. Restore is destructive. Use only
with a known-good backup.

### Backup directory migration performed on 2026-08-09

The existing 256 MB cold backup was moved from the repository-local
`backup/output` directory to:

```text
/Users/pandahorn/DevTools/Backup/jenkins-docker/jenkins_home_20260809-112146.tar.gz
```

The SHA-256 remained
`ce81b598163a1b2a5ebca7e677e9cba1b20c78d06a1fc2138fd0a0bdbf446163`,
and both `gzip -t` and a complete `tar tzf` listing passed after the move. The
now-empty `backup/output` directory was removed. No Jenkins volume or archive
content was deleted.

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

Check the socket ACL and verify access as the same user used by Pipeline jobs:

```bash
docker compose exec ci-arm64-docker getfacl -p /docker.sock
docker compose exec --user jenkins ci-arm64-docker docker version
```

Expected ACL entry:

```text
user:jenkins:rw-
```

If it is missing, rebuild the Docker agent image and recreate that service:

```bash
make rebuild-agent-docker
docker compose up -d --no-deps --force-recreate ci-arm64-docker
```

Recreating an SSH agent can change its host key. If Jenkins blocks the new
connection, review and trust the new key as described in section 11.

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

---

## 23. Jenkins LTS Upgrade Record: 2026-08-09

This section records the upgrade that was actually performed on this project.
It is both an audit record and the reference procedure for the next LTS update.

### 23.1 Goal and preserved architecture

The controller was upgraded from Jenkins `2.555.2 LTS` to the current stable
Jenkins `2.568.1 LTS`, while keeping Java 21 and the existing architecture:

```text
2.555.2-lts-jdk21
        -> 2.555.3-lts-jdk21
        -> 2.568.1-lts-jdk21
```

The intermediate `2.555.3` boot was used because the Jenkins `2.568.1` upgrade
guide describes the transition from `2.555.3`. Docker Compose, JCasC, Caddy,
named volumes, SSH agents, credentials, workspaces, and local TLS were retained.
No reset, volume deletion, image pruning, or agent base-image refresh was
performed.

Final controller references are kept consistent in:

* `controller/Dockerfile`
* `docker-compose.yml`
* `Makefile`

The final controller base image is:

```dockerfile
FROM jenkins/jenkins:2.568.1-lts-jdk21
```

The official base image resolved during this upgrade to:

```text
sha256:f4f65e6cd1405cd889b7f5ac33f9d5cdc2a099de6b87fe8a3933b9c5d53d1d02
```

### 23.2 Pre-upgrade baseline and rollback backup

Before any image or volume migration, the following checks passed:

```bash
docker compose config --quiet
docker compose ps -a
docker system df
```

All five project services were stopped. The Jenkins Home metadata reported
`2.555.2`, and 90 plugin files were present in the named volume.

A cold backup was then created in the original repository-local output
directory and later moved, without changing its contents, to:

```text
/Users/pandahorn/DevTools/Backup/jenkins-docker/jenkins_home_20260809-112146.tar.gz
```

Recorded validation data:

```text
size: 256 MiB
SHA-256: ce81b598163a1b2a5ebca7e677e9cba1b20c78d06a1fc2138fd0a0bdbf446163
```

The archive passed both `gzip -t` and `tar tzf` checks before the upgrade
continued. Backup archives contain Jenkins configuration, credentials, secrets,
users, and job history; keep them private and do not commit them.

### 23.3 Plugin compatibility work

The first `2.555.3` controller build intentionally stopped at the plugin
compatibility gate. The old top-level pin:

```text
junit:1403.vd9d1413fd205
```

was lower than the `junit:1413...` version required by the newly resolved
`matrix-project` dependency. No controller was started by that failed build.

`jenkins-plugin-cli --available-updates` was then run against both Jenkins
`2.555.3` and `2.568.1`. Both targets returned the same compatible top-level
updates, and `controller/plugins.txt` was updated to these tested pins:

```text
configuration-as-code:2116.v98dde145b_dce
credentials-binding:728.v902a_273b_8947
matrix-auth:3.3
docker-workflow:647.vf474049b_b_303
cloudbees-folder:6.1106.v3a_d9a_6d2465e
pipeline-graph-view:980.vb_db_0b_e5f683c
junit:1418.v67a_81935603c
```

The other ten direct plugin pins were unchanged. Both controller images then
built successfully with 90 resolved direct and transitive plugins.

The persisted `pipeline-graph-view` plugin had previously been upgraded from
the Jenkins UI, so its installed version differed from the image marker. The
controller now declares:

```yaml
PLUGINS_FORCE_UPGRADE: "true"
TRY_UPGRADE_IF_NO_MARKER: "true"
```

This makes the image-built `plugins.txt` the authoritative baseline even when
plugins were manually upgraded or have no older Docker version marker. Future
plugin upgrades should therefore be made in `controller/plugins.txt` and
verified by rebuilding the controller, not only through the Jenkins UI.

### 23.4 Executed core upgrade sequence

After the cold backup and compatible plugin lock update, the actual sequence
was:

```bash
# Temporary repository version: 2.555.3-lts-jdk21
docker compose config --quiet
docker compose --progress=plain build --no-cache jenkins-controller
docker compose up -d --no-build jenkins-controller
docker compose ps jenkins-controller
docker compose logs --no-color --tail=250 jenkins-controller

# Stop after the intermediate validation
docker compose stop jenkins-controller

# Final repository version: 2.568.1-lts-jdk21
docker compose config --quiet
docker compose --progress=plain build --no-cache --pull jenkins-controller
docker compose up -d --no-build jenkins-controller
docker compose logs --no-color --tail=260 jenkins-controller

# Start the unchanged proxy and agents without rebuilding them
docker compose up -d --no-build
```

The intermediate log confirmed `2.555.2 -> 2.555.3`. The final log confirmed
`2.555.3 -> 2.568.1`, followed by `Started all plugins`, `Completed
initialization`, and `Jenkins is fully up and running`.

The obsolete JCasC `remotingSecurity` entry was removed after Jenkins reported
that its `AdminWhitelistRule` setting no longer has any effect. The remaining
JCasC controller, authorization, credentials, location, and three-node
configuration was retained.

### 23.5 Executed verification and observed results

The following project checks were run after the final startup:

```bash
make verify
make verify-volumes
make verify-agents
make verify-docker-agent
```

Observed results:

* Jenkins controller reported `2.568.1` and Temurin Java `21.0.11`.
* Controller, Caddy, and all three agents reached `healthy` status.
* Jenkins authentication succeeded with the administrator from `.env`.
* All 90 plugins loaded; the seven updated direct plugin versions matched
  `plugins.txt`.
* JCasC retained the secured local realm and global matrix authorization.
* Jenkins API reported `ci-arm64-general`, `ci-arm64-alm`, and
  `ci-arm64-docker` online and not temporarily offline.
* Controller-to-agent TCP port 22 checks passed for all agents.
* Named volumes, read-only JCasC mount, Docker secret, tmpfs mounts, and Docker
  socket mount remained in their original architecture.
* Caddy returned HTTP/2 200 from `https://apps.localmac.net:8444/login`.

A temporary Pipeline named `upgrade-smoke-2-568-1` was created from
`examples/pipelines/check-agents.Jenkinsfile`. Its first run exposed a flaw in
the old verification method: `make verify-docker-agent` ran as root, while real
Pipeline steps run as `jenkins`, and the mounted OrbStack socket was
`root:root 0660`.

After explicit approval, only the `jenkins` user was granted a socket ACL:

```text
user:jenkins:rw-
```

The Docker agent image was rebuilt with the `acl` package, Compose was updated
to apply this ACL before starting `sshd`, and `make verify-docker-agent` was
changed to execute as `jenkins`. Pipeline run number 2 then completed with
`SUCCESS` across all three stages, including Docker Engine, Compose, and Buildx.
The temporary Jenkins task was deleted after the successful run.

The running Docker agent was repaired in place to preserve its already trusted
SSH host key. Its rebuilt image and updated entrypoint will apply the same ACL
automatically on the next container recreation. A future forced recreation may
generate a new SSH host key and require the administrator to trust it again.

### 23.6 Rollback procedure

Never start an older Jenkins core against a Jenkins Home that has already been
migrated by a newer core. Roll back the image and the matching Home backup
together.

For this upgrade, the rollback point is the `2.555.2` controller image plus:

```text
/Users/pandahorn/DevTools/Backup/jenkins-docker/jenkins_home_20260809-112146.tar.gz
```

Rollback sequence:

```bash
docker compose down

# Restore controller/Dockerfile, docker-compose.yml, Makefile,
# controller/plugins.txt, and casc/jenkins.yaml from the pre-upgrade revision.

make restore \
  ARCHIVE="/Users/pandahorn/DevTools/Backup/jenkins-docker/jenkins_home_20260809-112146.tar.gz"

docker compose up -d --no-build
docker compose ps
make verify
make verify-agents
```

If the old local controller image is unavailable, rebuild it from the
pre-upgrade revision before starting the restored volume. Do not run `make
reset`, `make reset-all`, or `docker compose down -v` during an upgrade or
rollback, because those commands delete the named volumes that preserve Jenkins
state.

### 23.7 Procedure for the next LTS upgrade

For future upgrades, repeat the same control points:

1. Read every skipped LTS upgrade guide and confirm the controller and all
   agents meet the required Java version.
2. Stop the stack, create a cold backup, verify the archive, and record its
   checksum.
3. Keep the old image and never reuse its tag for the new controller.
4. Ask `jenkins-plugin-cli` for updates using the target core version; update
   and pin direct plugins before building.
5. Treat any plugin dependency error as a stop condition.
6. If crossing an LTS baseline, boot and verify the final patch of the current
   LTS line first.
7. Start only the controller, inspect the full initialization log, then start
   Caddy and agents.
8. Verify as the real runtime identities, especially Docker access as
   `jenkins`, and run the three-agent smoke Pipeline.
9. Retain the old image and cold backup until the upgraded installation has
   survived normal jobs and at least one planned restart.
