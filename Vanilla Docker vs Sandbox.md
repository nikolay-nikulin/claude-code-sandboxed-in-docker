# Vanilla Docker vs Sandbox – Comparison (English Translation)

---

### 1. Process Isolation & Security Level  

| Criterion | Regular Docker Compose (`claude-docker-container`) | Docker Sandboxes (`claude-docker-sandbox`) |
|---|---|---|
| **Isolation boundary** | Linux namespaces + cgroups inside the shared Docker Desktop VM. | Hardware micro‑VM (microVM) via Apple Virtualization Framework (`sandboxd`). |
| **OS kernel** | All containers share a single Linux kernel inside Docker Desktop’s VM. A kernel vulnerability could theoretically allow a container escape. |
| **Access to Docker Daemon** | Requires mounting `/var/run/docker.sock` into the container. Any agent with socket rights can control the host Docker (effectively root on Docker Desktop). |
| **Network isolation (egress)** | Standard Docker bridge: outbound Internet is open, no built‑in request filtering. |

---

### 2. Resource Consumption & Performance  

| Criterion | Docker Compose (`main`) | Docker Sandboxes (`sbx`) |
|---|---|---|
| **RAM consumption** | Containers share memory of the common Docker Desktop VM. Overhead is minimal (a few tens of MB for a Node.js process). |
| **Start / Stop time** | Starting a pre‑built container is almost instantaneous (`docker compose up -d` ≈ 1–2 s). |
| **Disk I/O (VirtioFS)** | Mount `./:/workspace` via VirtioFS/gRPC FUSE in Docker Desktop. |
| **Start / Stop time** | Creating and booting a microVM takes a little longer (~3–5 s for a cold start of the kernel and virtualization). |
| **Disk I/O (VirtioFS)** | Direct mount through Apple Virtualization Framework (native VirtioFS on macOS), usually giving lower latency for intensive file operations (`git`, `node_modules`). |

---

### 3. Configuration & Developer Experience  

| Criterion | Docker Compose (`main`) | Docker Sandboxes (`sbx`) |
|---|---|---|
| **Manifest format** | Conventional `Dockerfile` + `docker-compose.yml`. Full control over apt packages, utilities, users, etc. |
| **Agent templates** | Image is built manually (`node:22‑bookworm‑slim` + `npm i -g @anthropic-ai/claude-code`). You must maintain versions yourself. |
| **Shim complexity** | Requires setting up `entrypoint.sh`, `chmod 666` on mounted sockets, manual UID/GID switching (`node`). |
| **Manifest format** | Declarative `sbxenv.yaml` or CLI commands (`sbx create`, `sbx env run`). |
| **Agent templates** | Official ready‑made templates (`docker/sandbox-templates:claude-code`) with pre‑configured environments. |
| **Shim complexity** | In `sbx`, the `agent` user is already pre‑configured with correct UID/GID; no need to juggle Docker sockets. |

---

### 4. Other Fundamental Differences

#### 4.1 Path Parity
- **Docker Compose:** Host repository is mounted at a fixed path `/workspace`. If an agent relies on absolute host paths (or generates file links), they do **not** match macOS paths (`/Users/john/...` ≠ `/workspace`).
- **`sbx`:** Project folder is mounted **at the exact same absolute path** as on the host, e.g. `/Users/path/to/claude-agentteam-sandboxed`. Log entries, links, and Git worktree paths are transparent and 100 % identical to macOS.

#### 4.2 Secrets & OAuth Tokens
- **Docker Compose:** Authorization tokens must be stored in a named volume (`claude-config:/home/node/.claude`) or passed via environment variables (`ANTHROPIC_API_KEY`).
- **`sbx`:** Native integration with `sbx secret` and a proxy. Credentials and API keys can be injected on‑the‑fly through a protected proxy gateway without ever persisting them in clear text inside the container.

#### 4.3 Launching Teammate‑agents in `cmux`
- **Docker Compose:** Shim runs `docker exec -u node -it claude-teams <cmd>`. The command executes inside the same container namespace via the Docker CLI.
- **`sbx`:** Shim runs `sbx exec -it -w <dir> claude-teams-sbx <cmd>`. The call goes through the native `sbx` binary, which talks directly to the microVM daemon via the Apple Hypervisor API.

---

### 5. When to Choose Which?

1. **Docker Compose (`main`)** is preferable when:
   - You need a classic Docker stack that can run on macOS, Linux servers, or CI/CD pipelines.
   - Full control over system libraries, compilers, and packages via a `Dockerfile` is required.
   - Machine resources are limited and you prefer not to launch separate microVMs.

2. **Docker Sandboxes (`sbx`)** shines when:
   - **Maximum isolation** of untrusted code is mandatory (hardware‑level microVM).
   - Tight **network traffic control** is critical (allow‑list proxy).
   - **Path identity** matters (`/Users/john/...`) so that local tools, links, and IDEs work without path mismatches (`/workspace`).

---
