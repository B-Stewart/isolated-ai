#!/bin/bash
set -euo pipefail
root=/opt/isoai/mixins/context7
mkdir -p "$root/vendor"
/opt/isoai/bin/tooling-npm install --prefix "$root/vendor" --no-audit --no-fund @upstash/context7-mcp@4.4.4
cat > "$root/context7" <<'EOF'
#!/bin/bash
set -euo pipefail
cli="$(readlink -f /opt/isoai/mixins/context7/vendor/node_modules/.bin/context7-mcp)"
exec /opt/isoai/bin/tooling-node "$cli" "$@"
EOF
chmod 0755 "$root/context7"
