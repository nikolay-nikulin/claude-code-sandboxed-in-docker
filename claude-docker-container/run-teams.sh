#!/usr/bin/env bash
# run-teams.sh
# Detects host cmux socket, exports environment, starts sandbox container,
# and attaches Claude Code in Agent Teams mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== [1/4] Detecting host cmux socket ==="

HOST_CMUX_SOCK=""

# 1. Check existing environment variable
if [ -n "${CMUX_SOCKET_PATH:-}" ] && [ -S "${CMUX_SOCKET_PATH}" ]; then
    HOST_CMUX_SOCK="${CMUX_SOCKET_PATH}"
fi

# 2. Check standard user state directory
if [ -z "$HOST_CMUX_SOCK" ]; then
    USER_ID=$(id -u)
    for candidate in \
        "$HOME/.local/state/cmux/cmux-${USER_ID}.sock" \
        "$HOME/.local/state/cmux/cmux-501.sock" \
        "$HOME/.local/state/cmux/cmux.sock" \
        "$HOME/.cmux/cmux.sock" \
        /tmp/cmux.sock \
        /tmp/cmux-${USER_ID}.sock \
        /tmp/cmux-*/cmux.sock
    do
        # Expand wildcards safely
        for match in $candidate; do
            if [ -S "$match" ]; then
                HOST_CMUX_SOCK="$match"
                break 2
            fi
        done
    done
fi

# 3. Fallback: inspect open sockets of running cmux processes
if [ -z "$HOST_CMUX_SOCK" ] && command -v lsof >/dev/null 2>&1; then
    SOCK_FROM_LSOF=$(lsof -c cmux 2>/dev/null | awk '/\.sock$/ {print $NF; exit}')
    if [ -n "$SOCK_FROM_LSOF" ] && [ -S "$SOCK_FROM_LSOF" ]; then
        HOST_CMUX_SOCK="$SOCK_FROM_LSOF"
    fi
fi

if [ -z "$HOST_CMUX_SOCK" ] || [ ! -S "$HOST_CMUX_SOCK" ]; then
    echo "Error: No active cmux socket found. Please ensure cmux is running on the host." >&2
    exit 1
fi

echo "Found cmux socket at: $HOST_CMUX_SOCK"
export HOST_CMUX_SOCK

# Detect cmux capability and active workspace/surface if not already exported
if [ -z "${CMUX_SOCKET_CAPABILITY:-}" ]; then
    for pid in $(pgrep claude 2>/dev/null; pgrep zsh 2>/dev/null; pgrep bash 2>/dev/null; pgrep cmux 2>/dev/null); do
        raw_env=$(ps -Eww "$pid" 2>/dev/null || true)
        found_cap=$(echo "$raw_env" | tr ' ' '\n' | grep -E '^CMUX_SOCKET_CAPABILITY=' | head -n 1 | cut -d= -f2-)
        if [ -n "$found_cap" ]; then
            export CMUX_SOCKET_CAPABILITY="$found_cap"
            echo "Found active cmux socket capability from process $pid"
            if [ -z "${CMUX_WORKSPACE_ID:-}" ]; then
                export CMUX_WORKSPACE_ID=$(echo "$raw_env" | tr ' ' '\n' | grep -E '^CMUX_WORKSPACE_ID=' | head -n 1 | cut -d= -f2-)
            fi
            if [ -z "${CMUX_SURFACE_ID:-}" ]; then
                export CMUX_SURFACE_ID=$(echo "$raw_env" | tr ' ' '\n' | grep -E '^CMUX_SURFACE_ID=' | head -n 1 | cut -d= -f2-)
            fi
            break
        fi
    done
fi

echo "=== [2/4] Ensuring script permissions ==="
chmod +x ./cmux ./tmux-cmux-shim.sh ./run-teams.sh ./entrypoint.sh 2>/dev/null || true

echo "=== [3/4] Building and launching sandbox container ==="
docker compose up -d --build

# Ensure socket, directory permissions, and updated shims inside container
docker compose exec -u root -T claude-teams sh -c "
    cp /workspace/tmux-cmux-shim.sh /usr/local/bin/tmux
    cp /workspace/cmux /usr/local/bin/cmux
    chmod +x /usr/local/bin/tmux /usr/local/bin/cmux
    chmod 666 /var/run/cmux.sock /var/run/docker.sock 2>/dev/null || true
    chmod 1777 /tmp 2>/dev/null || true
    mkdir -p /home/node/.claude
    chown -R node:node /home/node 2>/dev/null || true
"

echo "=== [4/4] Attaching to Claude Code Agent Teams ==="
exec docker compose exec -u node -it claude-teams claude --dangerously-skip-permissions --teammate-mode auto "$@"
