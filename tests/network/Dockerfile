FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends procps iproute2 wireguard-tools wireguard-go nftables iputils-ping curl ca-certificates python3 unbound dnsutils && rm -rf /var/lib/apt/lists/*
COPY tests/network /test
COPY deploy/templates/unbound.conf /production-unbound.conf
ENTRYPOINT ["python3", "/test/run.py"]
