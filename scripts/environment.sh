# Source from the repository root: . scripts/environment.sh
# Activate the user-owned toolchains installed in the managed cloud workspace, when present.
# Ordinary machines can use their existing PATH/toolchains unchanged.
if [ -d /workspace/toolchains/cargo/bin ] && [ -d /workspace/toolchains/rustup ]; then
  export CARGO_HOME=/workspace/toolchains/cargo
  export RUSTUP_HOME=/workspace/toolchains/rustup
  export PATH="/workspace/toolchains/cargo/bin:$PATH"
fi
if [ -d /workspace/toolchains/flutter/bin ]; then
  export PATH="/workspace/toolchains/flutter/bin:$PATH"
fi
