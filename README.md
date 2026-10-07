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
mkdir -p ~/claude-config       # 存放 CC 的配置/登录态，挂载后重建容器不用重新登录
mkdir -p ~/projects/my-project # 你的项目代码
```

### 3.2 启动容器（不写代理）

```bash
docker run -d \
  --name claude-code \
  -v "$HOME/claude-config:/home/developer/.claude" \
  -v "$HOME/projects/my-project:/workspace" \
  ghcr.io/hanlu1215/claude-code-docker:latest
```

- `-d` 后台运行；容器只跑 `sleep infinity`，用来待命；
- `-v ~/claude-config:...` 持久化配置和登录态；
- `-v ~/projects/my-project:/workspace` 把你的项目映射进容器。

### 3.3 进入容器并用 CC

```bash
docker exec -it claude-code bash
cd /workspace
claude
```

第一次运行 `claude` 会提示登录/配置，配置会写进挂载的 `~/claude-config`，以后不用重复。

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

---

## 4. 本地重新构建镜像

需要代理才能构建（不然拉包/安装容易失败）。代理只在构建期生效，不会写进最终镜像。

```bash
cd E:\AI-AGENT\claude-code-docker   # 或 Linux 下的对应目录

docker build \
  --build-arg HTTP_PROXY=http://127.0.0.1:7890 \
  --build-arg HTTPS_PROXY=http://127.0.0.1:7890 \
  --build-arg http_proxy=http://127.0.0.1:7890 \
  --build-arg https_proxy=http://127.0.0.1:7890 \
  -t claude-code:latest .
```

构建完用第 2 节的方法验证，然后用本地镜像启动：

```bash
docker run -d \
  --name claude-code \
  -v "$HOME/claude-config:/home/developer/.claude" \
  -v "$HOME/projects/my-project:/workspace" \
  claude-code:latest
```

> 注意：`--build-arg` 是构建期临时变量，不会留在镜像里；只有 Dockerfile 里写 `ENV http_proxy=...` 才会被永久写入镜像，应避免。

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
| 查 CC 版本 | `docker run --rm <镜像> claude --version` |
| 启动容器 | `docker start claude-code` |
| 进入容器 | `docker exec -it claude-code bash` |
| 运行 CC | `cd /workspace && claude` |
| 停止容器 | `docker stop claude-code` |
| 删除容器 | `docker rm -f claude-code` |
| 本地构建 | `docker build --build-arg ... -t claude-code:latest .` |

---

## 6. 说明：令牌与代理

- **GHCR 推送不需要你自己配置令牌**：GitHub Actions 每次运行自动生成临时 `GITHUB_TOKEN`，workflow 里声明 `permissions: packages: write` 即可推送。
- **Actions 构建不需要代理**：GitHub 云端服务器能直接访问 `https://claude.ai/install.sh`。
- **只有拉取 Private 镜像**才需要本地 `docker login ghcr.io`（用 `read:packages` 权限的 Token）。
