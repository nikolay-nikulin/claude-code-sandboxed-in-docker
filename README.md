# Claude Code Agent Teams in Sandboxes + cmux

Run **Claude Code Agent Teams** in isolated sandboxes on macOS while seamlessly projecting teammate agents into native **[cmux](https://cmux.com)** desktop split panes and windows.

This repository provides two distinct architectural approaches for running Claude Code Agent Teams:

1. **[`claude-docker-container/`](./claude-docker-container)**: **Docker Compose Container**
   - Single container based on `node:22-bookworm-slim`.
   - Runs as non-root `node` user with passwordless `sudo`.
   - Spawns teammates via `docker exec -u node -it claude-teams ...`.
   - Cross-platform compatible (macOS, Linux servers, CI/CD).
   - [Read container documentation](./claude-docker-container/README.md)

2. **[`claude-docker-sandbox/`](./claude-docker-sandbox)**: **Docker Sandboxes (`sbx`) microVM**
   - Hardware-level microVM isolation via Apple Virtualization Framework (`sandboxd`).
   - Exact host path parity (`/Users/john/...` mounts identically inside the microVM).
   - Built-in egress network proxy with domain allowlisting (`gateway.docker.internal:3128`).
   - Official template (`docker/sandbox-templates:claude-code`) and declarative `sbxenv.yaml`.
   - Spawns teammates via `sbx exec -it claude-teams-sbx ...`.
   - [Read sandbox documentation](./claude-docker-sandbox/README.md)

---

## In-Depth Architectural Comparison

For a complete breakdown of process isolation, security, path parity, performance, and resource consumption between the two approaches, see:

📖 **[Vanilla Docker vs Sandbox.md](./Vanilla Docker vs Sandbox.md)**

### Quick Summary

| Feature | Docker Compose (`claude-docker-container`) | Docker Sandboxes `sbx` (`claude-docker-sandbox`) |
| :--- | :--- | :--- |
| **Isolation Level** | Linux container namespaces & cgroups | Dedicated **Apple Virtualization microVM** |
| **Workspace Paths** | Remapped to `/workspace` | **Identical host path parity** (`/Users/john/...`) |
| **Egress Filtering** | Open Docker bridge | Controlled **network proxy** with allowlists |
| **Teammate Execution**| `docker exec -u node -it claude-teams ...` | `sbx exec -it claude-teams-sbx ...` |
| **Claude Binary** | Built into container image | Official pre-configured Docker Sandbox template |
| **Configuration** | `docker-compose.yml` + `Dockerfile` | Declarative `sbxenv.yaml` / CLI `sbx` |

---

## Directory Structure

```text
.
├── claude-docker-container/        # Docker Compose container implementation
│   ├── Dockerfile                  # node:22-bookworm-slim with Claude Code & cmux
│   ├── docker-compose.yml          # Compose specification with cmux socket mount
│   ├── entrypoint.sh               # Socket permission and runtime initialization
│   ├── run-teams.sh                # Launcher script with auto cmux detection
│   ├── cmux                        # Container-side cmux JSON-RPC client
│   ├── tmux-cmux-shim.sh           # tmux shim translating splits to cmux
│   └── README.md                   # Container documentation & troubleshooting
│
├── claude-docker-sandbox/          # Docker Sandboxes (sbx) microVM implementation
│   ├── sbxenv.yaml                 # Declarative sandbox specification
│   ├── run-teams.sh                # Launcher script managing sbx lifecycle
│   ├── cmux                        # Sandbox-side cmux JSON-RPC client
│   ├── tmux-cmux-shim.sh           # tmux shim translating splits to sbx exec
│   ├── Dockerfile                  # Standalone build definition
│   ├── docker-compose.yml          # Compose reference definition
│   └── README.md                   # Sandbox documentation & troubleshooting
│
├── Vanilla Docker vs Sandbox.md    # Detailed architectural and security comparison
├── GEMINI.md                       # Autonomous execution rules
└── README.md                       # Repository overview (this file)
```

---

## Quickstart

### Prerequisites
- **[cmux](https://cmux.com)** installed and running on macOS.
- **Docker Desktop** installed and running.
- For `claude-docker-sandbox`: Docker Desktop with Sandboxes feature enabled (`sbx` CLI).

### Option A: Run via Docker Compose Container
```bash
cd claude-docker-container
./run-teams.sh
```

### Option B: Run via Docker Sandboxes (`sbx`)
```bash
cd claude-docker-sandbox
./run-teams.sh
```
