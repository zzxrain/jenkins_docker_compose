# Jenkins Docker Compose CI/CD Lab

这是一个用于学习 CI/CD、模拟企业 Jenkins 架构，并为后续 Windchill / Codebeamer 集成做准备的本地 Docker Compose 环境。

## 架构概览

- **Jenkins Controller**：只负责调度、配置和凭据管理，不执行构建任务（`numExecutors: 0`）。
- **Caddy 反向代理**：提供本地 HTTPS 入口，便于模拟企业网关 / 统一入口。
- **静态 SSH Agents**：按职责拆分为通用、ALM/PLM、Docker 构建三类节点，便于后续按 label 隔离流水线。
- **JCasC**：通过 `casc/jenkins.yaml` 固化 Jenkins 基础配置，降低手工配置漂移。
- **Docker named volumes**：持久化 Jenkins Home、agent workspace、Caddy 数据。

## Prerequisites

- macOS with Docker Desktop or OrbStack
- Docker Compose v2
- GNU Make
- OpenSSH tools: `ssh-keygen`
- jq

macOS 安装 jq：
```bash
brew install jq
```

## 快速开始

```bash
make init
# 编辑 .env：至少替换 JENKINS_ADMIN_PASSWORD；必要时调整 JENKINS_URL / TZ
make validate
make up
```

## Post-start verification

```bash
make ps
make logs
```

访问：<https://jenkins.localhost:8444/> 或本机映射端口 <http://127.0.0.1:8089/>。

> 如果使用 `jenkins.localhost`，请确认浏览器可解析该地址；Caddy 使用内部 CA，首次访问会提示证书信任问题。

## 安全与生产化模拟建议

1. **凭据管理**
   - 不要提交 `.env` 或 `secrets/jenkins_agent_key`。
   - 当前 compose 使用 Docker secrets 将 Jenkins agent 私钥挂载到 controller。
   - 后续可替换为 Vault、云 KMS、企业密码库或 Jenkins Credentials Provider。
2. **权限模型**
   - JCasC 使用 matrix-auth，仅给管理员 `Overall/Administer`，认证用户默认只读。
   - 后续建议按团队增加 folder-level / job-level 权限，避免“所有登录用户都是管理员”。
3. **Agent 隔离**
   - `ci-arm64-docker` 挂载 `/var/run/docker.sock`，这等价于授予宿主机 Docker root 级权限。
   - 只把可信 Job 分配到 `docker buildx` label；更生产化的做法是使用远程 BuildKit、Kaniko、rootless Docker 或独立构建集群。
4. **入口与网络**
   - Jenkins HTTP 端口仅绑定 `127.0.0.1`，外部访问优先经 Caddy HTTPS。
   - 企业环境建议把 Caddy 替换或前置为 Nginx / F5 / Ingress，并接入 OIDC / SSO。
5. **可观测性**
   - Compose 已限制容器日志滚动，避免单机学习环境日志无限增长。
   - 后续建议接入 Prometheus、Grafana、Loki / ELK，并为 controller 磁盘、队列长度、executor 使用率设置告警。

## Windchill / Codebeamer 集成准备

建议把与 ALM/PLM 系统交互的流水线固定到 `ci arm64 linux alm codebeamer windchill` label，并遵循：

- API token、service account、证书放入 Jenkins Credentials，不写入 Jenkinsfile。
- 将 Windchill / Codebeamer 客户端脚本封装为共享库或独立 CLI，便于测试和复用。
- 为 API 调用设置超时、重试、幂等 key 和审计日志，避免 Jenkins 重跑造成重复变更。
- 在 Jenkins job 中记录外部系统对象 ID、变更单号、制品 SHA256、SBOM 链接等追溯信息。

## 常用命令

```bash
make init       # 创建 .env 和 SSH agent key
make validate   # 校验 compose 配置
make build      # 构建镜像
make up         # 启动或更新 stack
make down       # 停止 stack
make logs       # 查看日志
make backup     # 备份 Jenkins Home named volume
make restore ARCHIVE=backup/output/jenkins_home_YYYYmmdd-HHMMSS.tar.gz
```

## 升级建议

- Jenkins LTS、插件版本和 agent 基础镜像应成组升级，并先在临时 volume 中演练。
- 升级前执行 `make backup`，升级后检查 JCasC reload、agent 连接、关键流水线和插件兼容性。
- 插件版本固定在 `controller/plugins.txt`，便于回滚与差异审查。
- 建议在真实企业环境中定期导出 Jenkins 配置、凭据元数据清单和 job DSL / pipeline 定义。

Upgrade
```bash
make backup
# 修改 Jenkins 版本 / plugins.txt
make build
make up
make logs
```

Rollback
```bash
make down
# 恢复旧版本 Dockerfile / plugins.txt
make restore ARCHIVE=backup/output/xxx.tar.gz
make up
```

## 已知取舍

- SSH agent host key verification 当前使用 non-verifying 策略，便于本地容器重建；企业环境应改为固定 host key 或可信 CA。
- Docker socket agent 便于学习 Docker-in-Docker 替代方案，但安全边界弱；生产环境建议改造。
- 该仓库默认面向单机学习环境，不替代高可用 Jenkins controller 架构。

