FROM node:22-bookworm-slim

# Install system dependencies, docker-ce-cli, and sudo
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    git \
    procps \
    sudo \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Install cmux CLI client
COPY cmux /usr/local/bin/cmux
RUN chmod +x /usr/local/bin/cmux

# Install tmux compatibility shim
COPY tmux-cmux-shim.sh /usr/local/bin/tmux
RUN chmod +x /usr/local/bin/tmux

# Install entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Configure git safe directory for node user
RUN git config --system --add safe.directory /workspace

# Set environment variables for Agent Teams and fake tmux
ENV TMUX="/tmp/fake-tmux-sock,0,0" \
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
    CMUX_SOCKET_PATH="/var/run/cmux.sock" \
    HOME="/home/node"

WORKDIR /workspace

USER node

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
