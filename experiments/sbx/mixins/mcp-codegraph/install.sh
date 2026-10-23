#!/bin/bash
set -euo pipefail
root=/opt/isoai/mixins/codegraph
mkdir -p "$root/vendor"
/opt/isoai/bin/tooling-npm install --prefix "$root/vendor" --no-audit --no-fund @colbymchenry/codegraph@1.6.2
cat > "$root/codegraph" <<'EOF'
#!/bin/bash
set -euo pipefail
export CODEGRAPH_NO_DOWNLOAD=1
export PATH="/opt/isoai/tooling/node/bin:$PATH"
exec /opt/isoai/mixins/codegraph/vendor/node_modules/.bin/codegraph "$@"
EOF
chmod 0755 "$root/codegraph"
