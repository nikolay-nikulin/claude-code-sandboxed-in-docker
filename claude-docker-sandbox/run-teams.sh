#!/usr/bin/env bash
# run-teams.sh (Docker Sandboxes / sbx flavor)
# Detects host cmux socket, exports environment, initializes sbx sandbox,
# and attaches Claude Code in Agent Teams mode with native desktop splits.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR"

SANDBOX_NAME="${SBX_SANDBOX_NAME:-claude-teams-sbx}"

# Handle lifecycle management flags
if [ "${1:-}" = "--rm" ] || [ "${1:-}" = "--down" ]; then
    echo "Stopping and removing sandbox '${SANDBOX_NAME}'..."
    sbx stop "$SANDBOX_NAME" 2>/dev/null || true
    sbx rm --force "$SANDBOX_NAME" 2>/dev/null || true
    echo "Sandbox removed."
    exit 0
fi

if [ "${1:-}" = "--stop" ]; then
    echo "Stopping sandbox '${SANDBOX_NAME}'..."
    sbx stop "$SANDBOX_NAME"
    echo "Sandbox stopped."
    exit 0
fi

if ! command -v sbx >/dev/null 2>&1; then
    echo "Error: sbx CLI not found. Please install Docker Sandboxes (e.g. brew install sbx)." >&2
    exit 1
fi

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
HOST_CMUX_DIR="$(dirname "$HOST_CMUX_SOCK")"

# Detect cmux capability token from active processes
if [ -z "${CMUX_SOCKET_CAPABILITY:-}" ]; then
    found_cap=$(ps -Eww $(pgrep claude 2>/dev/null; pgrep zsh 2>/dev/null; pgrep cmux 2>/dev/null) 2>/dev/null | grep -o 'CMUX_SOCKET_CAPABILITY=[^ ]*' | head -n 1 | cut -d= -f2- || true)
    if [ -n "$found_cap" ]; then
        export CMUX_SOCKET_CAPABILITY="$found_cap"
        echo "Found active cmux socket capability: ${CMUX_SOCKET_CAPABILITY:0:15}..."
    fi
fi

echo "=== [2/4] Ensuring host script permissions ==="
chmod +x ./cmux ./tmux-cmux-shim.sh ./run-teams.sh

echo "=== [3/4] Ensuring sbx sandbox '${SANDBOX_NAME}' is ready ==="
if ! sbx ls 2>/dev/null | grep -qw "$SANDBOX_NAME"; then
    echo "Sandbox '${SANDBOX_NAME}' not found. Creating sandbox..."
    sbx create \
        --name "$SANDBOX_NAME" \
        -e CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
        -e TMUX="/tmp/fake-tmux-sock,0,0" \
        -e TMUX_PANE="%0" \
        -e CMUX_SOCKET_PATH="$HOST_CMUX_SOCK" \
        -e CMUX_SOCKET_CAPABILITY="${CMUX_SOCKET_CAPABILITY:-}" \
        -e SANDBOX_NAME="$SANDBOX_NAME" \
        claude \
        "$SCRIPT_DIR" \
        "$HOST_CMUX_DIR"
else
    echo "Sandbox '${SANDBOX_NAME}' already exists."
fi

echo "Configuring tmux-cmux shim inside '${SANDBOX_NAME}'..."
sbx exec -u root "$SANDBOX_NAME" mkdir -p /home/agent/.local/bin
sbx exec -u root "$SANDBOX_NAME" cp "${SCRIPT_DIR}/tmux-cmux-shim.sh" /home/agent/.local/bin/tmux
sbx exec -u root "$SANDBOX_NAME" cp "${SCRIPT_DIR}/cmux" /home/agent/.local/bin/cmux
sbx exec -u root "$SANDBOX_NAME" chown -R agent:agent /home/agent/.local/bin
sbx exec -u root "$SANDBOX_NAME" chmod +x /home/agent/.local/bin/tmux /home/agent/.local/bin/cmux

if [ "${1:-}" = "--test" ]; then
    echo "Testing inside sandbox:"
    sbx exec "$SANDBOX_NAME" tmux -V
    sbx exec "$SANDBOX_NAME" cmux ping
    echo "All checks passed successfully!"
    exit 0
fi

echo "=== [4/4] Attaching to Claude Code Agent Teams ==="
exec sbx exec -e TMUX_PANE="%0" -it -w "$SCRIPT_DIR" "$SANDBOX_NAME" claude --dangerously-skip-permissions --teammate-mode auto "$@"
