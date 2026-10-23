#!/bin/bash
set -euo pipefail

install_dir=/opt/isoai/opencode/vendor
mkdir -p "$install_dir" /opt/isoai/opencode/bin
/opt/isoai/bin/tooling-npm install --prefix "$install_dir" --no-audit --no-fund --omit=dev @opencode/cli@2.1.3
cat > /opt/isoai/opencode/bin/opencode <<'EOF'
#!/bin/bash
set -euo pipefail
export PATH="/opt/isoai/tooling/node/bin:$PATH"
exec /opt/isoai/opencode/vendor/node_modules/.bin/opencode "$@"
EOF
chmod 0755 /opt/isoai/opencode/bin/opencode
