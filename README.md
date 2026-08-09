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
│   │   ├── Dockerfile
│   │   └── persist-ssh-host-keys
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

> **Destructive, fresh installations only.** `make reset-all` deletes Jenkins
> Home, Agent workspace/SSH-host-key volumes, Caddy CA data, and local project
> images. Never use this sequence for an upgrade or rollback; use section 25.

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

### Host key persistence and reset behavior

Each agent stores its SSH server host keys in the root-owned
`.ssh-host-keys` directory inside that agent's named workspace volume. The
`persist-ssh-host-keys` helper restores those keys before `sshd` starts.
Consequently, ordinary container operations preserve the trusted identity:

```bash
docker compose down
docker compose up -d
docker compose up -d --force-recreate
```

The host key changes only when the corresponding named volume is removed, for
example by:

```bash
make reset
make reset-all
docker compose down -v
```

After a volume reset, the agent generates a new host key and Jenkins correctly
requires a new manual trust decision. The persisted private host keys remain
root-owned with mode `0600`; Pipeline jobs running as `jenkins` cannot read
them.

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

Ordinary Agent recreation retains its host key in the named workspace volume.
If the volume was deleted and Jenkins blocks the newly generated key, review
and trust it as described in section 11.

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

> **This sequence resets all persisted project state.** It is intended only for
> a new disposable lab. For an existing Jenkins controller, especially during
> an upgrade, follow section 25 and do not run `make reset-all`.

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

The controller was upgraded from Jenkins `2.555.2 LTS` to the then-targeted
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

The controller base image at the end of that upgrade was:

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
That lifecycle limitation was subsequently fixed during the `2.568.2` update;
see section 24.2.

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

Use the command-by-command runbook in section 25. It incorporates the failure
modes found during both upgrades and defines a stop condition for every unsafe
transition. Do not reconstruct an upgrade procedure from this historical
section alone.

---

## 24. Update History

This is the append-only chronological index of changes actually applied to the
running lab. Add each future Jenkins, plugin, agent, proxy, or operational
update as a new dated subsection. Keep section 23 as the detailed reference for
the first cross-LTS migration procedure.

### 24.1 2026-08-09 — Jenkins 2.555.2 to 2.568.1 LTS

Purpose:

* Move the controller to the Jenkins `2.568` LTS baseline while retaining JDK
  21, Compose, JCasC, named volumes, Caddy, credentials, and all three agents.
* Apply the required intermediate boot through `2.555.3`.
* Refresh and lock the compatible direct plugin baseline.

Executed sequence:

```text
2.555.2-lts-jdk21
        -> 2.555.3-lts-jdk21
        -> 2.568.1-lts-jdk21
```

Rollback archive:

```text
/Users/pandahorn/DevTools/Backup/jenkins-docker/jenkins_home_20260809-112146.tar.gz
SHA-256: ce81b598163a1b2a5ebca7e677e9cba1b20c78d06a1fc2138fd0a0bdbf446163
```

Results:

* Jenkins started on `2.568.1` with Temurin Java `21.0.11`.
* All 90 resolved plugins loaded and the 17 direct plugin pins were retained.
* Controller, Caddy, and all three agents reached `healthy`.
* The three-stage smoke Pipeline succeeded after Docker socket access was
  corrected for the real `jenkins` runtime identity.
* Caddy TLS lifetimes and the external backup directory were subsequently
  adjusted and recorded in their respective README sections.

This version was superseded later the same day after the Jenkins UI exposed the
2026-08-05 core security advisory and the official `2.568.2` LTS fix.

### 24.2 2026-08-09 — Jenkins 2.568.1 to 2.568.2 LTS

Reason:

* Jenkins `2.568.1` and earlier were affected by the core vulnerabilities in
  the [Jenkins Security Advisory 2026-08-05](https://www.jenkins.io/security/advisory/2026-08-05/).
* The advisory specifies `2.568.2` as the fixed LTS release. The patch retains
  the same `2.568` LTS baseline and JDK 21 runtime.

Changed controller references:

* `controller/Dockerfile`
* `docker-compose.yml`
* `Makefile`

The resulting controller uses:

```dockerfile
FROM jenkins/jenkins:2.568.2-lts-jdk21
```

The official base image resolved during the build to:

```text
sha256:8547df3b0db2803d158ecc9499207a056bb30c23fddc18bb5b4a4dc14e77dd09
```

Pre-upgrade rollback point:

```text
controller: local/jenkins-controller:2.568.1-lts-jdk21
archive: /Users/pandahorn/DevTools/Backup/jenkins-docker/jenkins_home_20260809-162121.tar.gz
size: 258 MiB
SHA-256: 4c1c2233af867aa9df827cc19ba96c7cb0dc3418f896da09f6adac8daf3768dd
```

The cold archive passed `gzip -t`, a complete `tar tzf` listing, and SHA-256
verification before the controller version changed.

Executed upgrade and verification:

1. Confirmed that the official `2.568.2-lts-jdk21` multi-architecture image tag
   was available.
2. Stopped all five services and created the external cold backup above.
3. Built `local/jenkins-controller:2.568.2-lts-jdk21`; plugin resolution against
   the target core completed successfully without changing the 17 direct pins.
4. Started only the controller and inspected its complete initialization log.
   It reported `2.568.1 -> 2.568.2`, `Started all plugins`, `Completed
   initialization`, and `Jenkins is fully up and running`.
5. Confirmed Jenkins `2.568.2`, Temurin Java `21.0.11`, 90 loaded plugin files,
   zero failed/disabled plugin markers, and exact agreement with every direct
   plugin pin.
6. Confirmed JCasC security, named volumes, read-only configuration, Docker
   secret, Docker socket ACL, and controller-to-agent TCP connectivity.
7. Confirmed all five Compose services were healthy, all three Jenkins agents
   were online, and `https://apps.localmac.net:8444/login` returned HTTP 200.
8. Confirmed the Jenkins management page no longer displayed the 2026-08-05
   core advisory and the HTTP response header reported `X-Jenkins: 2.568.2`.

The full-stack restart exposed an existing lifecycle defect: Agent containers
generated new SSH host keys on recreation while Jenkins correctly enforced
manual trust. The fix keeps each Agent's host keys in its root-only named
workspace volume and restores them before `sshd` starts. The verified ED25519
fingerprints are:

```text
ci-arm64-general  SHA256:7SAf9VbAn6v54NAb+spjhnYahFyHLEDOC3hN6XMsBbg
ci-arm64-alm      SHA256:tDJ6OgEnxoraEff6SUAatbkcaLf7NKg9bttEvxn0OJU
ci-arm64-docker   SHA256:UP2F9rouAm2kUqYszZE6o8BJw3d6k9Dn9LZnh4GYE+8
```

After one explicit review and trust operation, all three Agent containers were
force-recreated a second time. Their fingerprints remained identical and all
nodes reconnected without another trust action.

Finally, temporary Pipeline `upgrade-smoke-2-568-2` build number 1 ran
`examples/pipelines/check-agents.Jenkinsfile` and completed with `SUCCESS` on
the General, ALM, and Docker agents, including Docker Engine, Compose, and
Buildx calls as the `jenkins` user. The temporary job was deleted immediately
after verification.

Rollback for this patch requires both the `2.568.1` repository/image state and
the matching `jenkins_home_20260809-162121.tar.gz` archive above. Do not start
the older core against the Home directory after migration without restoring the
matching backup.

### 24.3 2026-08-09 — Post-upgrade runbook hardening

After the `2.568.2` upgrade, the documentation was reviewed against the exact
commands and failures observed during the work. Section 25 was added as the
authoritative manual upgrade runbook. In particular, it prevents these
previously encountered mistakes:

* selecting an already vulnerable LTS patch instead of checking the latest
  security advisory and current patch release;
* creating large backups inside the Git working tree;
* deleting named volumes with `make reset`, `make reset-all`, or
  `docker compose down -v` during an upgrade;
* building the Docker Agent concurrently with, or before, its local base image;
* using `--pull` for the Docker Agent's local-only base image;
* treating a root-only Docker socket test as proof that Pipeline jobs work;
* recreating Agents without understanding when their manually trusted SSH host
  identities are preserved or intentionally replaced;
* starting the full stack before the upgraded controller has passed standalone
  initialization checks; and
* rolling an image back without restoring its matching pre-upgrade Jenkins Home.

---

## 25. Safe Manual Jenkins Upgrade Runbook

This is the authoritative procedure for future controller upgrades. Run it
from the repository root. Replace the example versions and archive name with
the values for that upgrade; do not copy a historical version blindly.

### 25.1 Decide the exact target before editing files

1. Check the official [Jenkins LTS release line](https://www.jenkins.io/download/lts/),
   [LTS changelog](https://www.jenkins.io/changelog-stable/),
   [upgrade guides](https://www.jenkins.io/doc/upgrade-guide/), and
   [security advisories](https://www.jenkins.io/security/advisories/). Use the
   latest fixed patch in the intended LTS line. A version that was current a
   few days earlier may already be affected by a newly published advisory.
2. Confirm the exact official Docker tag exists, including its JDK suffix and
   required CPU architecture. This project intentionally remains on JDK 21:

   ```text
   jenkins/jenkins:<target>-lts-jdk21
   ```

   Inspect the manifest without changing the running stack:

   ```bash
   docker buildx imagetools inspect jenkins/jenkins:<target>-lts-jdk21
   ```

3. If only the patch changes inside the same LTS line, for example
   `2.568.1 -> 2.568.2`, upgrade directly. If crossing LTS baselines, read every
   skipped upgrade guide and first boot the latest patch of the current LTS line
   when Jenkins requires or recommends that intermediate step.
4. Confirm Java requirements for both controller and Agents before proceeding.

**Stop if:** the target tag does not exist for the host architecture, a skipped
upgrade guide has not been reviewed, or the required Java version is unknown.

### 25.2 Capture a clean baseline and rollback pair

Validate the current repository and runtime before stopping anything:

```bash
git status --short --branch
git rev-parse HEAD
docker compose config --quiet
docker compose ps -a
docker compose exec -T jenkins-controller java -version
docker compose exec -T jenkins-controller \
  java -jar /usr/share/jenkins/jenkins.war --version
docker image inspect "$(docker compose config --images | grep 'local/jenkins-controller:')" \
  --format '{{json .RepoTags}} {{.Id}} {{.Created}}'
for service in ci-arm64-general ci-arm64-alm ci-arm64-docker; do
  docker compose exec -T "$service" \
    ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
done
```

Record the current Git commit, controller image tag/ID, Jenkins version, Java
version, service health, and the three Agent ED25519 fingerprints. Commit or
intentionally set aside unrelated local changes so the pre-upgrade repository
state can be recovered exactly.

Create a **cold** Jenkins Home backup. Ordinary `docker compose down` removes
containers and the project network but preserves named volumes:

```bash
docker compose down
make backup
```

The script prints the exact archive path. It defaults to the host directory
below, outside the Git repository:

```text
$HOME/DevTools/Backup/jenkins-docker/
```

Copy the printed path into a shell variable and validate the entire archive:

```bash
UPGRADE_BACKUP="$HOME/DevTools/Backup/jenkins-docker/jenkins_home_YYYYmmdd-HHMMSS.tar.gz"
test -f "$UPGRADE_BACKUP"
gzip -t "$UPGRADE_BACKUP"
tar tzf "$UPGRADE_BACKUP" >/dev/null
shasum -a 256 "$UPGRADE_BACKUP"
```

Record the path, size, and SHA-256 in section 24 before changing the controller.
Do not use `make reset`, `make reset-all`, or `docker compose down -v`: all three
delete named volumes. `make reset-all` also removes local rollback images. Do
not use the old repository-local `backup/output` path.

**Stop if:** the baseline is already unhealthy, the archive is missing, either
archive integrity command fails, or the rollback image/revision cannot be
identified.

### 25.3 Change all authoritative version references together

Update the controller version in all three files:

```text
controller/Dockerfile  FROM jenkins/jenkins:<target>-lts-jdk21
docker-compose.yml     image: local/jenkins-controller:<target>-lts-jdk21
Makefile               CONTROLLER_IMAGE ?= local/jenkins-controller:<target>-lts-jdk21
```

Check that no active reference still points to the old version:

```bash
rg -n '<old-version>|<target-version>' \
  controller/Dockerfile docker-compose.yml Makefile
docker compose config --quiet
```

Historical entries in section 23 and section 24 must keep their original
versions. Do not mechanically replace the old version throughout README.

`controller/plugins.txt` contains the 17 direct plugin pins and is the
source-controlled plugin baseline. Review available plugin updates against the
target core. The controller build runs `jenkins-plugin-cli` for the target
image and resolves transitive dependencies; do not rely only on what the
currently running Jenkins UI offers.

**Stop if:** the three active version references disagree, Compose validation
fails, or a direct plugin update has not been checked against the target core.

### 25.4 Build the controller and treat plugin errors as fatal

Build only the controller first:

```bash
docker compose --progress=plain build --no-cache --pull jenkins-controller
```

The build must finish successfully, show `jenkins-plugin-cli` resolving the
plugin set, and produce the exact new local tag. Record the resolved official
base-image digest from the build output when maintaining the update history.

Do not rebuild Agents for a controller-only patch. If Agent source also changed,
build them **sequentially**, only after the base build has completely finished:

```bash
make rebuild-agent-base
make rebuild-agent-docker
```

The Docker Agent starts with:

```dockerfile
FROM local/jenkins-ssh-agent-base:debian-jdk21
```

Therefore, do not build the two Agent images concurrently and do not add
`--pull` to the Docker Agent build. Either mistake can build from a stale local
base or make Docker try and fail to pull `docker.io/local/...`.

**Stop if:** `jenkins-plugin-cli` reports a dependency/core-version conflict,
the resulting controller tag is wrong, or the Docker Agent build did not use
the newly completed local base image.

### 25.5 Start and approve the controller before the rest of the stack

Start only the upgraded controller against the backed-up Home:

```bash
docker compose up -d --no-build jenkins-controller
docker compose ps jenkins-controller
docker compose logs --no-color jenkins-controller
```

Wait for all of these messages, not merely a running container:

```text
Started all plugins
Completed initialization
Jenkins is fully up and running
```

Do not shorten this first review to a small log tail: the version-migration and
early plugin messages can occur well before the final readiness message.

Also check the recorded upgrade path and runtime versions:

```bash
docker compose exec -T jenkins-controller bash -lc '
  java -version
  java -jar /usr/share/jenkins/jenkins.war --version
  printf "lastExecVersion="
  cat /var/jenkins_home/jenkins.install.InstallUtil.lastExecVersion
  find /var/jenkins_home/plugins -maxdepth 1 -type f \
    \( -name "*.jpi" -o -name "*.hpi" \) | wc -l
  find /var/jenkins_home/plugins -maxdepth 1 -type f \
    \( -name "*.jpi.failed" -o -name "*.hpi.failed" \
       -o -name "*.jpi.disabled" -o -name "*.hpi.disabled" \) -print
'
make verify
```

Compare every direct pin in `controller/plugins.txt` with the installed plugin
manifests:

```bash
docker compose exec -T jenkins-controller bash -lc '
  set -euo pipefail
  while IFS=: read -r plugin expected; do
    [ -n "$plugin" ] || continue
    file="/var/jenkins_home/plugins/${plugin}.jpi"
    [ -f "$file" ] || file="/var/jenkins_home/plugins/${plugin}.hpi"
    [ -f "$file" ]
    actual=$(unzip -p "$file" META-INF/MANIFEST.MF |
      sed -n "s/^Plugin-Version: //p" | tr -d "\r" | head -1)
    printf "%s expected=%s actual=%s\n" "$plugin" "$expected" "$actual"
    [ "$actual" = "$expected" ]
  done < /usr/share/jenkins/ref/plugins.txt
'
```

This command exits nonzero for a missing or mismatched direct plugin. A
successful HTTP healthcheck alone does not prove that all plugins loaded.
Review the complete initialization log for failed plugins, JCasC exceptions,
detached-plugin warnings, or migration errors.

**Stop if:** the controller is unhealthy, the version is not the target,
`lastExecVersion` is wrong, a failed/disabled marker exists, a direct plugin pin
does not match, or the required initialization messages are absent.

### 25.6 Start Caddy and Agents without accidental rebuilds

After the controller passes standalone checks, start the unchanged services:

```bash
docker compose up -d --no-build
docker compose ps
```

All five services must become healthy. `--no-build` is intentional here: it
prevents Compose from unexpectedly rebuilding an Agent after the controlled
build phase.

Agent SSH host keys are restored from root-only `.ssh-host-keys` directories in
their named workspace volumes. Thus normal `down`, `up`, and `--force-recreate`
operations preserve the Jenkins-trusted identities. Compare these values with
the pre-upgrade fingerprints recorded in section 25.2:

```bash
for service in ci-arm64-general ci-arm64-alm ci-arm64-docker; do
  docker compose exec -T "$service" \
    ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
done
```

If a workspace volume was deleted, or the stack is being upgraded from a
revision that predates `persist-ssh-host-keys`, a new fingerprint is expected.
Review it and use **Manage Jenkins -> Nodes -> node -> Log / Launch agent ->
Trust SSH host key** once. Never disable verification merely to make an
unexpected key change disappear. A changed key without a known volume reset is
a stop condition and must be investigated.

When Agent images were changed, force-recreate them only after their sequential
builds and then repeat the fingerprint comparison:

```bash
docker compose up -d --no-build --force-recreate \
  ci-arm64-general ci-arm64-alm ci-arm64-docker
```

### 25.7 Verify the same paths and identities used by real jobs

Run the project checks:

```bash
make ps
make verify
make verify-volumes
make verify-agents
make verify-docker-agent
```

`make verify-docker-agent` intentionally runs as `jenkins`. Do not substitute a
root shell test: the `root:root 0660` Docker socket previously passed as root
while a real Pipeline failed. The Docker Agent entrypoint grants only the
`jenkins` user a socket ACL, which must be re-applied successfully on every
container start.

In Jenkins, select **New Item**, create a temporary **Pipeline**, copy the full
contents of `examples/pipelines/check-agents.Jenkinsfile` into **Pipeline ->
Script**, save, and select **Build Now**. It must finish with `SUCCESS` on
General, ALM, and Docker stages; the Docker stage must execute Engine, Compose,
and Buildx commands as `jenkins`. Delete the temporary job after recording the
result.

Then verify the externally used endpoint and target version:

```bash
curl --cacert certs/caddy-local-root.crt \
  -fsSI https://apps.localmac.net:8444/login \
  | grep -Ei '^(HTTP/|x-jenkins:)'
```

Confirm HTTP 200, `X-Jenkins: <target>`, all three nodes online, JCasC security
still enabled, and no applicable core advisory on **Manage Jenkins**. Finally,
perform one planned full-stack container recreation, not merely `restart`, and
repeat health, fingerprint, node, Pipeline, and HTTPS checks:

```bash
docker compose down
docker compose up -d --no-build
```

This catches host-key and startup lifecycle defects that an in-place process
restart or first boot cannot reveal.

**The upgrade is complete only when:** the standalone controller gate, all five
service healthchecks, three-node Pipeline, real-identity Docker check, HTTPS
check, security-advisory check, and planned-restart check all pass.

### 25.8 Roll back image and Home as one unit

Do not start an older Jenkins image against Home after a newer core has migrated
it. Restore both halves of the rollback pair captured in section 25.2:

1. Stop the stack with `docker compose down`.
2. Restore the exact pre-upgrade Git revision, or revert all controller/plugin/
   JCasC changes to that revision.
3. Confirm the old local controller image still exists; rebuild it from the old
   revision if necessary.
4. Restore the matching cold archive:

   ```bash
   make restore ARCHIVE="$UPGRADE_BACKUP"
   ```

5. Start without rebuilding and repeat the normal verification:

   ```bash
   docker compose up -d --no-build
   make ps
   make verify
   make verify-volumes
   make verify-agents
   make verify-docker-agent
   ```

`make restore` is destructive: it stops Compose, clears the Jenkins Home named
volume, and extracts the selected archive. It does not restore repository files
or the controller image, which is why those must be returned to the matching
pre-upgrade state first.

Retain the old image and verified cold backup until the new installation has
survived normal jobs and at least one planned restart. Append the target,
backup checksum, image digest, commands, results, exceptions, and rollback pair
to section 24 so the next upgrade starts from an auditable state.
