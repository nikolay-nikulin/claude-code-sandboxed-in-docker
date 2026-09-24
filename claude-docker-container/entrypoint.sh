#!/usr/bin/env bash
# entrypoint.sh
# Fix permissions on mounted sockets and state files, then exec command

set -e

# Fix permissions on mounted Unix sockets so non-root 'node' user can read/write them
sudo chmod 666 /var/run/cmux.sock 2>/dev/null || true
sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

# Ensure proper permissions for /tmp
sudo chmod 1777 /tmp 2>/dev/null || true

# Ensure persistent directory structure and permissions
sudo mkdir -p /home/node/.claude
sudo chown -R node:node /home/node 2>/dev/null || true

# Symlink ~/.claude.json into persistent volume so config persists
if [ ! -s /home/node/.claude/claude.json ]; then
    echo "{}" > /home/node/.claude/claude.json
fi
if [ ! -L /home/node/.claude.json ]; then
    ln -sf /home/node/.claude/claude.json /home/node/.claude.json
fi

# Clean up any stale teammate runner or command files in /tmp
rm -f /tmp/teammate_* /tmp/fake-tmux-sock* 2>/dev/null || true

exec "$@"
