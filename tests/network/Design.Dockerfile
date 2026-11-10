FROM dtvpn-network-lab
RUN apt-get update && apt-get install -y --no-install-recommends chromium nodejs && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["node", "scripts/render-design.cjs"]
