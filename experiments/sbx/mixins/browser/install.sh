#!/bin/bash
set -euo pipefail
root=/opt/isoai/mixins/browser
mkdir -p "$root/vendor" "$root/bin"
/opt/isoai/bin/tooling-npm install --prefix "$root/vendor" --no-audit --no-fund agent-browser@0.39.2
cat > "$root/bin/agent-browser" <<'EOF'
#!/bin/bash
set -euo pipefail
cli="$(readlink -f /opt/isoai/mixins/browser/vendor/node_modules/.bin/agent-browser)"
exec /opt/isoai/bin/tooling-node "$cli" "$@"
EOF
chmod 0755 "$root/bin/agent-browser"
cat > "$root/install-browser" <<'EOF'
#!/bin/bash
set -euo pipefail
exec /opt/isoai/mixins/browser/bin/agent-browser install "$@"
EOF
chmod 0755 "$root/install-browser"
