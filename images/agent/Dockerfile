# syntax=docker/dockerfile:1.19
# The syntax directive is load-bearing: COPY --exclude (used below to keep the
# tool installers out of the runtime image) needs frontend 1.19 or newer.

FROM node:24-bookworm-slim

# ------------------------------------------------------------------
# Base: shared OS and runtime utilities only.
#
# No pentest tool is installed here. A tool is a named capability with its own
# directory under tools/, and that directory owns its install script, its
# version pins and its documentation. If a package serves the appliance as an
# operating system it belongs in this block; if it is a capability the agent
# points at a target, it belongs in tools/<name>/.
#
# The slim base ships no procps, no iproute2 and no python3 — an agent that
# cannot run `uptime`, `ps`, `ip` or a Python script is crippled for
# diagnostics, so the appliance carries a curated set rather than the distro
# catalogue.
# ------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl wget ca-certificates gnupg openssl \
        procps iproute2 lsof file less tree bc nano vim-tiny tzdata \
        git jq yq ripgrep fd-find unzip zip p7zip-full xz-utils dos2unix \
        libxml2-utils iputils-ping traceroute mtr-tiny netcat-openbsd socat telnet \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Python for the base environment and for every tool venv. PEP 668 makes
# bookworm's system interpreter externally managed, so the general-purpose
# packages have to live in a venv as well; putting that venv in front of the
# system one means `python3` behaves normally for a human or an agent writing
# an ad-hoc script, without --break-system-packages.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv build-essential libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# General-purpose Python only. Tool libraries are deliberately absent: each
# tool's packages live in its own venv under /opt/venvs, so nothing here can
# conflict with a tool's dependency resolution. To use a tool's library,
# run that tool's interpreter — /opt/venvs/<tool>/bin/python3.
ENV PY_BASE=/opt/py
RUN python3 -m venv "$PY_BASE" \
    && "$PY_BASE/bin/pip" install --no-cache-dir --upgrade pip \
    && "$PY_BASE/bin/pip" install --no-cache-dir \
        requests pyyaml jinja2 dnspython beautifulsoup4 lxml
ENV PATH="$PY_BASE/bin:$PATH"

# Shared helpers for the per-tool install scripts: hash-checked fetch,
# unpack, install_bins, expose_venv. Not copied into the final image.
COPY tools/_lib/install-helpers.sh /tmp/tool-install-helpers.sh

# ------------------------------------------------------------------
# Tools. One copy/run pair per tool, alphabetical.
#
# Adding a tool: create tools/<name>/ with an install.sh and an AGENTS.md,
# then add its two lines here. Nothing else in the repository needs to change.
#
# Each script runs in its own layer, so editing one tool rebuilds that tool and
# the layers after it, not the whole toolchain. Editing a file that is not an
# install.sh (documentation, most often) rebuilds nothing, because the docs are
# copied once at the end.
# ------------------------------------------------------------------
COPY tools/arjun/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

# The driver script sits beside its installer and is placed by it, so the
# two change together: the CLI and the version of Playwright it launches are
# one unit.
COPY tools/browser/browser /opt/browser/browser
COPY tools/browser/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/clairvoyance/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/commix/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/dalfox/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/dirb/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/dnsx/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/feroxbuster/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/ffuf/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/gobuster/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/graphql-cop/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/gowitness/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/hashcat/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/httpx/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/hydra/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/impacket/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/john/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/jwt_tool/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/katana/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/masscan/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/metasploit/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/mitmproxy/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/naabu/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/netexec/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/nmap/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/nuclei/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/oauth2c/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/pypykatz/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/scapy/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/schemathesis/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/sqlmap/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/subfinder/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/testssl.sh/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/trivy/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/trufflehog/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/tshark/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/wafw00f/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/websocat/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

COPY tools/whatweb/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

# Data, not a tool: the wordlists every discovery tool reads. Kept last so a
# wordlist refresh does not invalidate the toolchain above it.
COPY tools/words/install.sh /tmp/install.sh
RUN bash /tmp/install.sh

# ------------------------------------------------------------------
# Operator documentation, baked into the runtime image.
#
# The build instructions are excluded — the install scripts and the template
# they are copied from. They are not documentation, and the agent has no use for
# a script that would reinstall a pinned tool over the pinned version.
# Everything else in tools/ lands at /tools/, mirroring the layout in this
# repository so the relative links between documents keep working.
#
# The pattern must be recursive, and the trailing `*` is what covers both
# `install.sh` and `install.sh.template`. A bare `--exclude=install.sh` is
# accepted and silently matches nothing here, which ships every installer into
# the runtime image with no warning — verified on host01, where `**/install.sh`
# removed all 32 and the bare form removed none.
#
# This copy sits after every tool layer on purpose. A documentation edit
# changes this layer and nothing else.
# ------------------------------------------------------------------
COPY --exclude=**/install.sh* tools/ /tools/

# ------------------------------------------------------------------
# Agent runtime
# ------------------------------------------------------------------
ARG CODE_SERVER_VERSION=4.137.0
ARG CODE_SERVER_SHA256=9303165b7fd43532091922f77e2f119ff2fa109c6b6f1c3c966fb02f3d6d9c8b

# Web VS Code over the shared working directory. Pinned and hash-verified:
# this binary sits on the agent's tool surface, so its provenance is part of
# the image rather than an install script run at build time.
RUN curl -fsSL -o /tmp/code-server.tar.gz \
        "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    && echo "${CODE_SERVER_SHA256}  /tmp/code-server.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/code-server.tar.gz -C /opt \
    && mv "/opt/code-server-${CODE_SERVER_VERSION}-linux-amd64" /opt/code-server \
    && ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server \
    && rm /tmp/code-server.tar.gz

# The harness itself, not a pentest tool: it belongs to the agent runtime.
RUN npm install -g @deepseek-ai/dsh@0.1.5-rc.1

# DSH state lives on the host bind mount so Greg can inspect it and the
# GUI persists across rebuilds; the shared working directory is where
# test notes and AGENTS.md live, visible to both Greg and the agent.
ENV DSH_HOME=/data/dsh

# The VPN gateway's control API. Baked in rather than injected from the
# stack environment: the agent shares the gateway's network namespace, so
# the address is always loopback on a fixed port, and the kill switch
# opens exactly that port to the sandbox network and drops it everywhere
# else. There is no credential — reachability is the control. See
# images/vpn-gateway/api.py.
ENV VPN_API_URL=http://localhost:8080

WORKDIR /working

COPY settings.seed.yaml /app/settings.seed.yaml
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
