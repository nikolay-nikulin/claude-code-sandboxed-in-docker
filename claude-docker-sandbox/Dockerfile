FROM node:22-bookworm-slim

# Install system dependencies and docker-ce-cli
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    git \
    procps \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Install cmux CLI client
COPY cmux /usr/local/bin/cmux
RUN chmod +x /usr/local/bin/cmux

# Install tmux compatibility shim
COPY tmux-cmux-shim.sh /usr/local/bin/tmux
RUN chmod +x /usr/local/bin/tmux

# Set environment variables for Agent Teams and fake tmux
ENV TMUX="/tmp/fake-tmux-sock,0,0" \
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
    CMUX_SOCKET_PATH="/var/run/cmux.sock"

WORKDIR /workspace

CMD ["sleep", "infinity"]
