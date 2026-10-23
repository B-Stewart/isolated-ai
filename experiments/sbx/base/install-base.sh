#!/bin/bash
set -euo pipefail

bun_version=$1 bun_sha=$2 mise_version=$3 mise_sha=$4 node_version=$5
if [[ "$(dpkg --print-architecture)" != amd64 ]]; then
  echo "This scaffold currently supports Linux amd64 only" >&2
  exit 1
fi
apt-get update
apt-get install -y --no-install-recommends \
  bash ca-certificates curl git 'gh=2.*' jq openssh-client ripgrep unzip sudo socat tini xz-utils
rm -rf /var/lib/apt/lists/*

mkdir -p /opt/isoai/bin /opt/isoai/mise /etc/isoai/mise /var/lib/isoai/mise
curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${bun_version}/bun-linux-x64.zip" -o /tmp/bun.zip
echo "${bun_sha}  /tmp/bun.zip" | sha256sum -c -
unzip -q /tmp/bun.zip -d /tmp/bun
install -m 0755 /tmp/bun/bun-linux-x64/bun /usr/local/bin/bun
rm -rf /tmp/bun /tmp/bun.zip

curl -fsSL "https://github.com/jdx/mise/releases/download/v${mise_version}/mise-v${mise_version}-linux-x64.tar.gz" -o /tmp/mise.tar.gz
echo "${mise_sha}  /tmp/mise.tar.gz" | sha256sum -c -
tar -xzf /tmp/mise.tar.gz -C /tmp
install -m 0755 /tmp/mise/bin/mise /usr/local/bin/mise
rm -rf /tmp/mise /tmp/mise.tar.gz

export MISE_CONFIG_DIR=/etc/isoai/mise MISE_DATA_DIR=/opt/isoai/mise MISE_STATE_DIR=/var/lib/isoai/mise
mise use --global --pin "node@${node_version}"
mise reshim
node_dir="/opt/isoai/mise/installs/node/${node_version}"
mkdir -p /opt/isoai/tooling
ln -s "$node_dir" /opt/isoai/tooling/node
cat > /opt/isoai/bin/tooling-node <<'EOF'
#!/bin/sh
exec /opt/isoai/tooling/node/bin/node "$@"
EOF
cat > /opt/isoai/bin/tooling-npm <<'EOF'
#!/bin/sh
export PATH="/opt/isoai/tooling/node/bin:$PATH"
exec /opt/isoai/tooling/node/bin/npm "$@"
EOF
chmod 0755 /opt/isoai/bin/tooling-node /opt/isoai/bin/tooling-npm
