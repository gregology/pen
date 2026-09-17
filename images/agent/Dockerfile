FROM node:24-bookworm-slim

ARG CODE_SERVER_VERSION=4.137.0

# The agent's tool surface. Everything here is a Debian package from a
# security-supported repo: adding a tool is a line in this list, not a
# special case anywhere else in the platform. The base is slim by design,
# but "slim" means no procps and no iproute2 — an agent that cannot run
# `uptime`, `ps`, or `ip` is crippled for diagnostics, so the appliance
# carries a curated set rather than the distro's full catalogue.
#   system      — process/system/file inspection the agent reaches for first
#   network     — connectivity diagnosis and target access (ssh, not just curl)
#   assessment  — scanners and offline cracking
#   dev/build   — cloning and compiling PoCs, scripting, data wrangling
RUN apt-get update && apt-get install -y --no-install-recommends \
        nmap curl whois dnsutils gobuster ca-certificates \
        procps net-tools iproute2 lsof psmisc file less tree bc nano vim-tiny tzdata \
        iputils-ping traceroute mtr-tiny tcpdump netcat-openbsd socat telnet openssh-client \
        masscan whatweb dirb sqlmap hydra john \
        git python3 python3-pip python3-venv build-essential libssl-dev \
        jq yq ripgrep fd-find unzip zip p7zip-full xz-utils dos2unix \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Web VS Code over the shared working directory. Pinned and hash-verified:
# this binary sits on the agent's tool surface, so its provenance is part
# of the image, not an install script run at build time.
RUN curl -fsSL -o /tmp/code-server.tar.gz \
        "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    && echo "9303165b7fd43532091922f77e2f119ff2fa109c6b6f1c3c966fb02f3d6d9c8b  /tmp/code-server.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/code-server.tar.gz -C /opt \
    && mv "/opt/code-server-${CODE_SERVER_VERSION}-linux-amd64" /opt/code-server \
    && ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server \
    && rm /tmp/code-server.tar.gz

RUN npm install -g @deepseek-ai/dsh@0.1.5-rc.1

# DSH state lives on the host bind mount so Greg can inspect it and the
# GUI persists across rebuilds; the shared working directory is where
# test notes and AGENTS.md live, visible to both Greg and the agent.
ENV DSH_HOME=/data/dsh
WORKDIR /working

COPY settings.seed.yaml /app/settings.seed.yaml
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
