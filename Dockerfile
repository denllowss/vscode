FROM codercom/code-server:latest

# Metadata
LABEL maintainer="admin@example.com" \
      description="Ultra optimized code-server - No Auth, Root User" \
      version="1.0"

# Switch to root
USER root

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Jakarta \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CODE_SERVER_PORT=6080 \
    SHELL=/bin/bash

# Single layer optimization - Install semua dependencies sekaligus
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl git vim nano htop net-tools iputils-ping \
    build-essential gcc g++ make \
    python3 python3-pip python3-dev \
    nodejs npm \
    ca-certificates gnupg \
    zip unzip tar gzip \
    && npm install -g yarn pnpm \
    && pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
              /tmp/* \
              /var/tmp/* \
              /usr/share/doc/* \
              /usr/share/man/* \
              /var/cache/apt/archives/*

# Create optimal directory structure
RUN mkdir -p /root/workspace \
             /root/.local/share/code-server/extensions \
             /root/.config/code-server \
    && chmod -R 755 /root

# Minimal config untuk performa maksimal
RUN printf 'bind-addr: 0.0.0.0:6080\nauth: none\ncert: false\ndisable-telemetry: true\ndisable-update-check: true\n' \
    > /root/.config/code-server/config.yaml

# VS Code settings untuk optimasi
RUN mkdir -p /root/.local/share/code-server/User && \
    echo '{\n\
  "telemetry.telemetryLevel": "off",\n\
  "workbench.enableExperiments": false,\n\
  "extensions.autoUpdate": false,\n\
  "files.autoSave": "afterDelay",\n\
  "files.autoSaveDelay": 1000,\n\
  "editor.formatOnSave": true,\n\
  "editor.minimap.enabled": false,\n\
  "git.autofetch": false,\n\
  "search.followSymlinks": false\n\
}' > /root/.local/share/code-server/User/settings.json

# Set working directory
WORKDIR /root/workspace

# Expose port
EXPOSE 6080

# Healthcheck ringan
HEALTHCHECK --interval=60s --timeout=5s --start-period=10s --retries=2 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:6080/healthz || exit 1

# Optimized startup command
CMD exec code-server \
    --bind-addr 0.0.0.0:6080 \
    --auth none \
    --disable-telemetry \
    --disable-update-check \
    --disable-workspace-trust \
    /root/workspace
