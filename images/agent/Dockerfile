FROM node:24-bookworm-slim

ARG CODE_SERVER_VERSION=4.137.0
ARG NUCLEI_VERSION=3.11.1
ARG NUCLEI_SHA256=ea63d4ae232808cd7c6bc00d0142428e231fab59dae01042246097d195835ab6
ARG HTTPX_VERSION=1.12.0
ARG HTTPX_SHA256=9d8439e8b6c9aa7d1e2314817a392e00d5178da3af5652f7475f88868f418f76
ARG KATANA_VERSION=1.7.0
ARG KATANA_SHA256=fe1142d92f418549338ea46d67a472124878482e225d279e9a42700c75d76a4d
ARG SUBFINDER_VERSION=2.16.0
ARG SUBFINDER_SHA256=1b7f9c608e9a5bd59e609a5e09710d63c5485e92d3d49dc2c16eb4fdbe10cb60
ARG DNSX_VERSION=1.3.1
ARG DNSX_SHA256=438b964653056dd51dcfe614b1a16f8bced3cc48a1d27bc07cc6fdf2ef2a9533
ARG NAABU_VERSION=2.6.1
ARG NAABU_SHA256=018c4c9884dea971eda860435ede3021d1150732f34cfd245498c6726d8cab90
ARG FFUF_VERSION=2.3.0
ARG FFUF_SHA256=b2a3c725fcb9da175159682f54d6e9149f2905b00d84d155e7efc5d599975ceb
ARG FEROXBUSTER_VERSION=2.13.1
ARG FEROXBUSTER_SHA256=0978619a10049ccaad290b2d1241bc4d8a6aac18da07d6231186fb9d343f99de
ARG DALFOX_VERSION=3.2.3
ARG DALFOX_SHA256=6f4c68b01c13d6eb2fded1a14827701651451b9225c679a70689ec2dcaab231f
ARG TESTSSL_VERSION=3.2.4
ARG TESTSSL_SHA256=98528f8a0ac07f1e226efaa8ead438247df8efcb8fee4e056a937ab82a305490
ARG TRUFFLEHOG_VERSION=3.97.5
ARG TRUFFLEHOG_SHA256=e3d97199c565c37ca6152750197f667e08ae6a1edf5911fbdec168622b28620c
ARG TRIVY_VERSION=0.74.0
ARG TRIVY_SHA256=cf1e32ec8d4d8823e023096a28cadb14f5b5123ce03f201fb633c5b76aa712dd
ARG SECLISTS_VERSION=2026.1
ARG NUCLEI_TEMPLATES_VERSION=10.4.9
ARG NUCLEI_TEMPLATES_SHA256=d7cd989935f9a84943cba8a193f567db37626dbf4e526ff57ba5b1f24badd5d6
ARG COMMIX_VERSION=4.1
ARG COMMIX_SHA256=d71e6a98231c2eb434eb9cc1b835523ad5618578309e2f835c40d767f2af79de

# The agent's tool surface. Adding a tool is a line in one of the lists below,
# never a special case anywhere else in the platform.
#   system      — process/system/file inspection the agent reaches for first
#   network     — connectivity diagnosis and target access (ssh, not just curl)
#   assessment  — scanners, credential attacks, offline cracking
#   dev/build   — cloning and compiling PoCs, scripting, data wrangling
# The slim base ships no procps, no iproute2, and no python3 — an agent that
# cannot run `uptime`, `ps`, `ip`, or a Python script is crippled for
# diagnostics, so the appliance carries a curated set rather than the distro
# catalogue.
RUN apt-get update && apt-get install -y --no-install-recommends \
        nmap curl wget whois dnsutils gobuster openssl \
        procps net-tools iproute2 lsof psmisc file less tree bc nano vim-tiny tzdata \
        iputils-ping traceroute mtr-tiny tcpdump netcat-openbsd socat telnet openssh-client \
        masscan whatweb dirb sqlmap hydra john \
        git python3 python3-pip python3-venv build-essential libssl-dev \
        jq yq ripgrep fd-find unzip zip p7zip-full xz-utils dos2unix \
        ca-certificates gnupg libxml2-utils \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# Tools that are security-sensitive to their era — a stale TLS or hash-mode
# engine reports "safe" for configurations that are not — come from Debian
# bookworm at whatever version it ships, or from upstream. Where bookworm's
# version is materially stale, the upstream release wins and the package is
# not installed at all, so there is exactly one binary per capability.
#   tshark/scapy   — bookworm versions are current; apt is the cheaper path
#   hashcat        — bookworm (6.2.6); upstream 7.x moves faster than worth
#                    re-implementing as a source build here. PoCL supplies the
#                    OpenCL ICD: hashcat aborts with no ICD even for CPU work.
#   testssl.sh     — upstream 3.2.4, bookworm has 3.0.8. It hard-requires
#                    hexdump (bsdextrautils) and only Recommends it, so
#                    --no-install-recommends installs a testssl that cannot
#                    start.
#   browser libs   — katana -hl and httpx screenshots download a Chromium build
#                    (go-rod) and then fail to launch it: Debian slim ships
#                    none of the shared libraries Chromium links against. The
#                    libraries are here so a runtime-downloaded browser can
#                    actually render; the "silently returns zero endpoints"
#                    failure they prevent is worse than the image cost.
RUN apt-get update && apt-get install -y --no-install-recommends \
        tshark python3-scapy hashcat ocl-icd-libopencl1 pocl-opencl-icd \
        bsdextrautils \
        libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libatspi2.0-0 \
        libcups2 libgbm1 libxkbcommon0 libxcomposite1 libxdamage1 \
        libxrandr2 libxfixes3 libpango-1.0-0 libcairo2 libasound2 \
    && rm -rf /var/lib/apt/lists/*

# Metasploit ships an omnibus .deb that carries its own Ruby, so "lucid" in
# the repo stanza is a legacy label, not a distro requirement. The pin keeps
# an unrelated metasploit* package from ever winning a version comparison.
RUN curl -fsSL https://apt.metasploit.com/metasploit-framework.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/metasploit-framework.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/metasploit-framework.gpg] https://apt.metasploit.com/ lucid main" \
        > /etc/apt/sources.list.d/metasploit-framework.list \
    && printf 'Package: metasploit*\nPin: origin apt.metasploit.com\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/pin-metasploit.pref \
    && apt-get update \
    && apt-get install -y --no-install-recommends --allow-downgrades metasploit-framework \
    && rm -rf /var/lib/apt/lists/*

# Upstream releases, every one hash-verified at build time. The binaries are
# pinned because these tools sit on the agent's attack surface: a silently
# swapped download is a backdoor in the container that probes Greg's projects.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eux; \
    get() { \
      local url="$1" sha="$2" out="$3" bin="$4"; \
      curl -fsSL -o "/tmp/${out}" "$url"; \
      echo "${sha}  /tmp/${out}" | sha256sum -c -; \
      rm -rf /tmp/unpack; mkdir -p /tmp/unpack; \
      case "$out" in \
        *.zip) unzip -q "/tmp/${out}" -d /tmp/unpack ;; \
        *)     tar -xzf "/tmp/${out}" -C /tmp/unpack ;; \
      esac; \
      find /tmp/unpack -type f \( -perm -u+x -o -name "${bin}" \) \
        -exec install -m 0755 {} "/usr/local/bin/${bin}" \; ; \
      test -x "/usr/local/bin/${bin}"; \
      rm -rf "/tmp/${out}" /tmp/unpack; \
    }; \
    get "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/nuclei_${NUCLEI_VERSION}_linux_amd64.zip" \
        "$NUCLEI_SHA256" nuclei.zip nuclei; \
    get "https://github.com/projectdiscovery/httpx/releases/download/v${HTTPX_VERSION}/httpx_${HTTPX_VERSION}_linux_amd64.zip" \
        "$HTTPX_SHA256" httpx.zip httpx; \
    get "https://github.com/projectdiscovery/katana/releases/download/v${KATANA_VERSION}/katana_${KATANA_VERSION}_linux_amd64.zip" \
        "$KATANA_SHA256" katana.zip katana; \
    get "https://github.com/projectdiscovery/subfinder/releases/download/v${SUBFINDER_VERSION}/subfinder_${SUBFINDER_VERSION}_linux_amd64.zip" \
        "$SUBFINDER_SHA256" subfinder.zip subfinder; \
    get "https://github.com/projectdiscovery/dnsx/releases/download/v${DNSX_VERSION}/dnsx_${DNSX_VERSION}_linux_amd64.zip" \
        "$DNSX_SHA256" dnsx.zip dnsx; \
    get "https://github.com/projectdiscovery/naabu/releases/download/v${NAABU_VERSION}/naabu_${NAABU_VERSION}_linux_amd64.zip" \
        "$NAABU_SHA256" naabu.zip naabu; \
    get "https://github.com/ffuf/ffuf/releases/download/v${FFUF_VERSION}/ffuf_${FFUF_VERSION}_linux_amd64.tar.gz" \
        "$FFUF_SHA256" ffuf.tar.gz ffuf; \
    get "https://github.com/epi052/feroxbuster/releases/download/v${FEROXBUSTER_VERSION}/x86_64-linux-feroxbuster.zip" \
        "$FEROXBUSTER_SHA256" feroxbuster.zip feroxbuster; \
    get "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz" \
        "$TRUFFLEHOG_SHA256" trufflehog.tar.gz trufflehog

# Upstream .debs carry their own dependencies, so they install with apt rather
# than a dpkg that would leave the package database inconsistent.
RUN set -eux; \
    curl -fsSL -o /tmp/dalfox.deb \
        "https://github.com/hahwul/dalfox/releases/download/v${DALFOX_VERSION}/dalfox-v${DALFOX_VERSION}-linux-x86_64.deb"; \
    echo "${DALFOX_SHA256}  /tmp/dalfox.deb" | sha256sum -c -; \
    curl -fsSL -o /tmp/trivy.deb \
        "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb"; \
    echo "${TRIVY_SHA256}  /tmp/trivy.deb" | sha256sum -c -; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/dalfox.deb /tmp/trivy.deb; \
    rm -f /tmp/dalfox.deb /tmp/trivy.deb; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL -o /tmp/testssl.tar.gz \
        "https://github.com/testssl/testssl.sh/archive/refs/tags/v${TESTSSL_VERSION}.tar.gz"; \
    echo "${TESTSSL_SHA256}  /tmp/testssl.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/testssl.tar.gz -C /opt; \
    mv "/opt/testssl.sh-${TESTSSL_VERSION}" /opt/testssl.sh; \
    ln -s /opt/testssl.sh/testssl.sh /usr/local/bin/testssl.sh; \
    chmod +x /opt/testssl.sh/testssl.sh; \
    rm /tmp/testssl.tar.gz

# commix is deliberately NOT taken from PyPI: the package published there as
# `commix` is an unrelated installer stub that shadows the real tool and does
# nothing. The upstream release is the only source of the command-injection
# scanner, and it is a plain Python tree run from its own directory.
RUN set -eux; \
    curl -fsSL -o /tmp/commix.tar.gz \
        "https://github.com/commixproject/commix/archive/refs/tags/v${COMMIX_VERSION}.tar.gz"; \
    echo "${COMMIX_SHA256}  /tmp/commix.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/commix.tar.gz -C /opt; \
    mv "/opt/commix-${COMMIX_VERSION}" /opt/commix; \
    chmod +x /opt/commix/commix.py; \
    ln -s /opt/commix/commix.py /usr/local/bin/commix; \
    python3 -c "import ast,sys; ast.parse(open('/opt/commix/commix.py').read())"; \
    rm /tmp/commix.tar.gz

# One virtualenv for every Python tool. PEP 668 makes bookworm's system Python
# externally managed, so this is the only correct place to install them; it is
# on PATH ahead of the system interpreter so `python3` and the tools agree on
# which site-packages they are using.
#
# mitmproxy is pinned to 11.0.0 because 11.1.0 and later require Python >= 3.12
# and the base image is bookworm (Python 3.11).
#
# impacket has no version pin on purpose: NetExec depends on an unreleased
# impacket revision (0.14.0.dev0) and pip cannot satisfy both that and a
# release pin in one resolution, so one version has to win — and the version
# NetExec is tested against is the one that keeps both tools working. Letting
# pip resolve it also leaves `pip check` clean.
#
# aardwolf is pinned to the newest release that still ships a manylinux wheel.
# 0.2.14 is sdists only, and its Rust build does not compile with bookworm's
# rustc 1.63; taking the wheel avoids both a multi-minute build and a Rust
# toolchain in the image.
#
# bcrypt is pinned below 4.1: passlib 1.7.4 (pulled in by mitmproxy) probes its
# bcrypt backend with a >72-byte password, and bcrypt 4.1+ raises instead of
# truncating, which makes every mitmproxy entry point exit at import time.
#
# dploot is pinned below 4: netexec declares `dploot>=3.1.0` with no upper
# bound, and dploot 4 moved its SMB module, so the unpinned install produces a
# netexec whose SMB protocol dies at import with ModuleNotFoundError. The
# version banner still prints, so only a real run reveals it.
#
# The venv's `httpx` console script is renamed because it shadows
# ProjectDiscovery's `httpx` binary on PATH — two unrelated tools with the same
# name, and the network mapper is the one that has to win. The library stays
# installed: certipy-ad and other transitive dependencies import it.
ENV VIRTUAL_ENV=/opt/pen-venv
RUN python3 -m venv --system-site-packages "$VIRTUAL_ENV" \
    && "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --upgrade pip \
    && "$VIRTUAL_ENV/bin/pip" install --no-cache-dir \
        "mitmproxy==11.0.0" \
        "bcrypt==4.0.1" \
        "aardwolf==0.2.13" \
        "dploot<4" \
        arjun \
        wafw00f \
        pypykatz \
        "git+https://github.com/Pennyw0rth/NetExec@v1.5.1" \
    && mv "$VIRTUAL_ENV/bin/httpx" "$VIRTUAL_ENV/bin/httpx-httpclient" \
    && "$VIRTUAL_ENV/bin/pip" check
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# The scanner is inert without templates, and `nuclei -update-templates` is not
# usable at build time (it is a self-update path that needs a writable template
# directory and a GitHub release to exist). The template archive is fetched and
# verified directly instead, so a build either produces a scanner that works or
# fails loudly. Refresh at runtime with `nuclei -update-templates`.
RUN set -eux; \
    curl -fsSL -o /tmp/nuclei-templates.tar.gz \
        "https://github.com/projectdiscovery/nuclei-templates/archive/refs/tags/v${NUCLEI_TEMPLATES_VERSION}.tar.gz"; \
    echo "${NUCLEI_TEMPLATES_SHA256}  /tmp/nuclei-templates.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/nuclei-templates.tar.gz -C /root; \
    mv "/root/nuclei-templates-${NUCLEI_TEMPLATES_VERSION}" /root/nuclei-templates; \
    rm /tmp/nuclei-templates.tar.gz; \
    test "$(find /root/nuclei-templates -name '*.yaml' | wc -l)" -gt 1000

# Wordlists are data, not toolchain — pinned by tag so a finding is
# reproducible, and kept in one well-known place for every discovery tool.
RUN set -eux; \
    curl -fsSL -o /tmp/seclists.tar.gz \
        "https://github.com/danielmiessler/SecLists/archive/refs/tags/${SECLISTS_VERSION}.tar.gz"; \
    mkdir -p /opt/wordlists; \
    tar -xzf /tmp/seclists.tar.gz -C /opt/wordlists; \
    mv "/opt/wordlists/SecLists-${SECLISTS_VERSION}" /opt/wordlists/SecLists; \
    ln -s /opt/wordlists/SecLists /opt/wordlists/current; \
    rm /tmp/seclists.tar.gz

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
