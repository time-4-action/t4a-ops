#!/usr/bin/env bash
#
# t4a-docker-ports — keep the internet off Docker's published ports.
#
# Docker publishes ports with DNAT rules that run before firewalld, so
# "ports: 3001:3000" answers from the internet and bypasses Cloudflare.
# nginx reaches every app over localhost, which never passes DOCKER-USER, so
# dropping new outside connections to these ports breaks nothing.
#
# Usage (as root): t4a-docker-ports
# Run by t4a-docker-ports.service after every Docker start. Idempotent: it
# rebuilds its own chain and adds the jumps from DOCKER-USER only once.
#
# To open a port to the internet on purpose, remove it from PORTS.

set -euo pipefail

CHAIN=T4A-DOCKER-PORTS
INTERFACES=(eth0 eth1)
PORTS=(3000 3001 3002 3005 3333 4000 4545 8000 8001 8090)

iptables -N "$CHAIN" 2>/dev/null || iptables -F "$CHAIN"
for port in "${PORTS[@]}"; do
  # --ctorigdstport is the host port as the client sent it, before Docker's DNAT.
  iptables -A "$CHAIN" -p tcp -m conntrack --ctstate NEW --ctorigdstport "$port" -j DROP
done

for iface in "${INTERFACES[@]}"; do
  iptables -C DOCKER-USER -i "$iface" -j "$CHAIN" 2>/dev/null \
    || iptables -I DOCKER-USER -i "$iface" -j "$CHAIN"
done

echo "blocked outside access to ports ${PORTS[*]} on ${INTERFACES[*]}"
