FROM node:24-bookworm-slim

# Baseline recon tooling per the V1 plan — adding a tool is a package
# here, not a special case anywhere else in the platform. nikto is
# absent from bookworm main and deliberately not pulled from elsewhere
# for V1.
RUN apt-get update && apt-get install -y --no-install-recommends \
        nmap curl whois dnsutils gobuster \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @deepseek-ai/dsh@0.1.5-rc.1

# DSH state lives on the host bind mount so Greg can inspect it and the
# GUI persists across rebuilds.
ENV DSH_HOME=/data/dsh
WORKDIR /data

COPY settings.seed.yaml /app/settings.seed.yaml
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
