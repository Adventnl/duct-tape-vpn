FROM dtvpn-network-lab
RUN apt-get update && apt-get install -y --no-install-recommends g++-mingw-w64-x86-64-posix && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["sh"]
