#!/bin/bash
# Egress allowlist for an agentic dev container.
# Default-deny output; allow loopback, established/related, DNS, and resolved IPs of allowlisted hosts.
# Requires --cap-add=NET_ADMIN at container run time.
#
# Extra hosts: comma-separated FIREWALL_EXTRA_HOSTS env var.
#
# Limitation: hosts are resolved to IPs at init time. CDN-backed targets (npm, GitHub objects)
# rotate IPs over hours/days; if a long-lived container starts seeing previously-working hosts
# blocked, re-run this script to re-resolve.
set -euo pipefail

ALLOWED_HOSTS=(
  "registry.npmjs.org"
  "api.anthropic.com"
  "console.anthropic.com"
  "github.com"
  "api.github.com"
  "objects.githubusercontent.com"
  "raw.githubusercontent.com"
  "codeload.github.com"
)

if [ -n "${FIREWALL_EXTRA_HOSTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$FIREWALL_EXTRA_HOSTS"
  for h in "${EXTRA[@]}"; do
    ALLOWED_HOSTS+=("$h")
  done
fi

# Reset (|| true on re-invocation: built-in chains may have no rules to flush, no user chains to delete)
iptables -F || true
iptables -X || true
ipset destroy allowed-hosts 2>/dev/null || true

# Default-deny output, allow input/forward minimally
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Established/related
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# DNS so we can resolve allowlisted hosts after rules are in place
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allowlist ipset
ipset create allowed-hosts hash:ip family inet hashsize 1024 maxelem 65536

for host in "${ALLOWED_HOSTS[@]}"; do
  # `|| true` guards against `set -o pipefail` aborting on hosts with no A records (e.g. AAAA-only,
  # NXDOMAIN, or transient DNS hiccups). Without it, one bad host would drop the script mid-flight
  # leaving default-DROP active with no allowlist applied — silently bricking all egress.
  for ip in $(dig +short "$host" A | grep -E '^[0-9]' || true); do
    ipset add allowed-hosts "$ip" -exist
  done
done

iptables -A OUTPUT -m set --match-set allowed-hosts dst -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-hosts dst -p tcp --dport 80  -j ACCEPT

iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

echo "Firewall initialized: ${#ALLOWED_HOSTS[@]} hosts allowlisted"
