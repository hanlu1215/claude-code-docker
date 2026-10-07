# claude-code-docker

把 Claude Code 打包成 Docker 镜像，方便在任何 Linux 机器上直接使用。

镜像由 GitHub Actions 手动触发构建并发布到 GHCR（**不会**在 push 时自动构建）：

```
ghcr.io/hanlu1215/claude-code-docker
```

每次构建会同时发布 3 个标签（三者指向同一个镜像）：

| 标签 | 示例 | 用途 |
| --- | --- | --- |
| `latest` | `ghcr.io/hanlu1215/claude-code-docker:latest` | 永远拉最新 |
| Claude Code 版本号 | `ghcr.io/hanlu1215/claude-code-docker:2.1.292` | 锁定某个 CC 版本 |
| Git SHA | `ghcr.io/hanlu1215/claude-code-docker:1f85906…` | 精确定位某次构建 |

镜像内已包含 `curl`、`git`、`ca-certificates`、`sudo`，非 root 用户 `developer`，工作目录 `/workspace`。

---

## 1. 拉取镜像

```bash
# 最新版（日常用这个）
docker pull ghcr.io/hanlu1215/claude-code-docker:latest

# 指定 Claude Code 版本
docker pull ghcr.io/hanlu1215/claude-code-docker:2.1.292

# 精确指定某次 Git 构建
docker pull ghcr.io/hanlu1215/claude-code-docker:1f859069e9fdfae23614d9f2b52c36f1e29d443a
```

如果镜像设为 Private，需要先登录（Token 在 GitHub → Settings → Developer settings → Personal access tokens 生成，勾选 `read:packages`）：

```bash
echo "你的GitHub Token" | docker login ghcr.io -u 你的GitHub用户名 --password-stdin
```

---

## 2. 验证镜像是否正确

```bash
# 1) 看镜像在不在
docker images | grep claude-code-docker

# 2) 不启动容器，直接查 Claude Code 版本
docker run --rm ghcr.io/hanlu1215/claude-code-docker:latest claude --version

# 3) 确认基础环境正常
docker run --rm ghcr.io/hanlu1215/claude-code-docker:latest sh -c "whoami && pwd && git --version"
```

预期结果：

- 第 2 条会输出类似 `2.1.292 (Claude Code)` 的版本号，说明 CC 已装好；
- 第 3 条输出 `developer`、`/workspace` 和 git 版本号，说明用户和工作目录正常。

---

## 3. 日常使用

### 3.1 准备两个目录（只需一次）

```bash
mkdir -p ~/config              # 存放 CC 的配置/登录态，挂载后重建容器不用重新登录，可以把之前配置好的settings.json放这里
mkdir -p ~/projects            # 你的项目代码
```

### 3.2 启动容器（不写代理）

```bash
docker run -d \
  --init \
  --name claude-code \
  --hostname claude \
  -v "$HOME/config:/home/developer/.claude" \
  -v "$HOME/projects:/workspace" \
  ghcr.io/hanlu1215/claude-code-docker:latest
```

- `-d` 后台运行；容器只跑 `sleep infinity`，用来待命；
- `--init` 注入 tini 作为 PID 1，负责转发信号、回收僵尸进程；
- `--hostname claude` 让容器内的主机名显示为 `claude`（跟 `--name` 无关，`--name` 只影响宿主机上的容器名）；
- `-v ~/config:...` 持久化配置和登录态；
- `-v ~/projects:/workspace` 把你的项目映射进容器。

> **为什么必须加 `--init`？** 容器主进程是 `sleep infinity`，它被当作 PID 1 运行。
> 作为 PID 1 的进程默认会忽略没有注册处理器的信号，`docker stop` 发来的 SIGTERM 会被吞掉，
> 只能等 10 秒宽限期结束后被 SIGKILL 强杀 —— 表现为 `docker stop` 卡住几秒或报错。
> `--init` 让 tini 充当 PID 1，收到 SIGTERM 后正常转发，容器即可立即、干净地退出。

### 3.3 进入容器并用 CC

```bash
docker exec -it claude-code bash
cd /workspace
claude
```

第一次运行 `claude` 会提示登录/配置，配置会写进挂载的 `~/config`，以后不用重复。

### 3.4 需要联网/装包时，在容器内开代理

```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890

# 不需要时关掉
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
```

> 代理只在容器内临时生效（关闭终端即失效），**不要**写进 `docker run`。

### 3.5 退出、停止、再次使用

```bash
exit                     # 退出容器，容器仍在后台运行
docker stop claude-code  # 停止容器
docker start claude-code # 下次启动
docker exec -it claude-code bash
```

换项目时，把 `-v` 里的宿主目录换成新项目路径重建容器即可（`docker rm -f claude-code` 后重新 `docker run`）。

> 重建容器时别忘了保留 `--init`，否则 `docker stop` 又会卡在 10 秒宽限期后强杀。

### 3.6 用 docker-compose（推荐，免记长命令）

仓库根目录已带 `docker-compose.yml`，把 `config/` 和 `workspace/` 放在它旁边即可：

```
你的目录/
├── docker-compose.yml
├── config/      → /home/developer/.claude
└── workspace/   → /workspace
```

`docker-compose.yml` 已包含 `--init`（即 `init: true`）、`hostname: claude`、两个挂载和 `restart: unless-stopped`，所以只需：

```bash
cd 你的目录

docker compose up -d        # 启动（老版 Compose 用 docker-compose up -d）
docker compose ps           # 查看状态
docker exec -it claude-code bash
```

> 相对路径是相对 **Compose 文件所在目录**解析的，所以整个目录搬到别处也不用改配置。

首次可先 `docker compose up`（不加 `-d`）前台看启动日志，确认无误后 `Ctrl+C`，再 `docker compose up -d`。

确认参数真的生效：

```bash
docker inspect claude-code --format '{{.Config.Init}}'        # 返回 true 说明 init 已生效
docker inspect claude-code --format '{{.Config.Hostname}}'    # 返回 claude 说明主机名已生效
docker inspect claude-code --format '{{json .Mounts}}'        # 核对两个挂载路径
```

---

## 4. 本地重新构建镜像

需要代理才能构建（不然拉包/安装容易失败）。代理只在构建期生效，不会写进最终镜像。

先拿到源码（已经克隆过就直接 `cd claude-code-docker`）：

```bash
git clone https://github.com/hanlu1215/claude-code-docker.git
cd claude-code-docker
```

然后在该目录下构建（各平台命令相同，代理地址换成你自己的）：

```bash
docker build \
  --build-arg HTTP_PROXY=http://127.0.0.1:7890 \
  --build-arg HTTPS_PROXY=http://127.0.0.1:7890 \
  --build-arg http_proxy=http://127.0.0.1:7890 \
  --build-arg https_proxy=http://127.0.0.1:7890 \
  -t claude-code:latest .
```

> 上面是单行命令用 `\` 换行。**PowerShell 里要把行尾的 `\` 换成反引号 `` ` ``**（或者干脆写成一整行）；CMD 里也得写成一整行。

构建完用第 2 节的方法验证，然后用本地镜像启动：

```bash
docker run -d \
  --init \
  --name claude-code \
  --hostname claude \
  -v "$HOME/config:/home/developer/.claude" \
  -v "$HOME/projects:/workspace" \
  claude-code:latest
```

> 注意：`--build-arg` 是构建期临时变量，不会留在镜像里；只有 Dockerfile 里写 `ENV http_proxy=...` 才会被永久写入镜像，应避免。
>
> PowerShell 里没有 `$HOME`，请把 `$HOME/config` 换成 `$env:USERPROFILE\config`，`$HOME/projects` 同理。

### 4.1 升级 Claude Code

不需要改 Dockerfile。去 **GitHub → Actions → Build and Push Docker Image → Run workflow** 重新跑一次，它会重新构建、安装当时的 CC，并打上 `:latest`、`:新版本号`、`:<新的Git SHA>`；旧版本标签依然可用。

### 4.2 改了 Dockerfile

```bash
git add .
git commit -m "update docker image"
git push
```

推送代码**不会**触发构建。改完 Dockerfile 后，去 **GitHub → Actions → Build and Push Docker Image → Run workflow**（选择 `main` 分支）手动点一次，才会构建并发布新镜像。

---

## 5. 常用命令速查

| 操作 | 命令 |
| --- | --- |
| 拉最新镜像 | `docker pull ghcr.io/hanlu1215/claude-code-docker:latest` |
| 查 CC 版本 | `docker run --rm ghcr.io/hanlu1215/claude-code-docker:latest claude --version` |
| 启动容器 | `docker start claude-code` |
| 重建容器 | `docker run -d --init --name claude-code --hostname claude -v "$HOME/config:/home/developer/.claude" -v "$HOME/projects:/workspace" <镜像>` |
| 进入容器 | `docker exec -it claude-code bash` |
| 运行 CC | `cd /workspace && claude` |
| Compose 启动 | `docker compose up -d`（在 `docker-compose.yml` 所在目录） |
| Compose 停止 | `docker compose down` |
| 停止容器 | `docker stop claude-code` |
| 删除容器 | `docker rm -f claude-code` |
| 本地构建 | `docker build --build-arg ... -t claude-code:latest .` |

---

## 6. 说明：令牌与代理

- **GHCR 推送不需要你自己配置令牌**：GitHub Actions 每次运行自动生成临时 `GITHUB_TOKEN`，workflow 里声明 `permissions: packages: write` 即可推送。
- **Actions 构建不需要代理**：GitHub 云端服务器能直接访问 `https://claude.ai/install.sh`。
- **只有拉取 Private 镜像**才需要本地 `docker login ghcr.io`（用 `read:packages` 权限的 Token）。
