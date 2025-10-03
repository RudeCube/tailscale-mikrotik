#!/bin/bash
# Copyright (c) 2025 NodeSpace
# All rights reserved.
# Use of this source code is governed by a BSD-style license.

set -m

# Enable IP forwarding at runtime only (no file bloat)
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Set root password
echo "root:${PASSWORD}" | chpasswd

# Install routes
IFS=',' read -ra SUBNETS <<< "${ADVERTISE_ROUTES}"
for s in "${SUBNETS[@]}"; do
  ip route add "$s" via "${CONTAINER_GATEWAY}"
done

# Optional: Perform Tailscale update if enabled
if [[ -n "${UPDATE_TAILSCALE}" ]]; then
  /usr/local/bin/tailscale update --yes
fi

# Default login server if not set
if [[ -z "$LOGIN_SERVER" ]]; then
  LOGIN_SERVER=https://controlplane.tailscale.com
fi

# Optional: Run custom startup script
if [[ -n "$STARTUP_SCRIPT" ]]; then
  bash "$STARTUP_SCRIPT" || exit $?
fi

# # Start tailscaled in background
# /usr/local/bin/tailscaled ${TAILSCALED_ARGS} &

# # Wait for tailscaled to become responsive
# until /usr/local/bin/tailscale status >/dev/null 2>&1; do
#   sleep 0.1
# done

# # Bring up tailscale if not already connected
# if ! /usr/local/bin/tailscale status | grep -q "Logged in as"; then
#   /usr/local/bin/tailscale up \
#     --authkey="${AUTH_KEY}" \
#     --login-server "${LOGIN_SERVER}" \
#     --advertise-routes="${ADVERTISE_ROUTES}" \
#     ${TAILSCALE_ARGS}
# fi

# Start tailscaled and bring tailscale up
/usr/local/bin/tailscaled ${TAILSCALED_ARGS} &
until /usr/local/bin/tailscale up \
  --authkey="${AUTH_KEY}" \
	--login-server "${LOGIN_SERVER}" \
	--advertise-routes="${ADVERTISE_ROUTES}" \
  ${TAILSCALE_ARGS}
do
	sleep 0.1
done

echo "Tailscale started"

# Clean and add DNAT rule to forward 100.64.0.0/10 → 172.17.0.1
iptables -t nat -D PREROUTING -d 100.64.0.0/10 -j DNAT --to-destination ${CONTAINER_GATEWAY} 2>/dev/null || true
iptables -t nat -C PREROUTING -d 100.64.0.0/10 -j DNAT --to-destination ${CONTAINER_GATEWAY} 2>/dev/null || iptables -t nat -A PREROUTING -d 100.64.0.0/10 -j DNAT --to-destination ${CONTAINER_GATEWAY}

# Allow forwarding to the target only if not already allowed
iptables -C FORWARD -d ${CONTAINER_GATEWAY} -j ACCEPT 2>/dev/null || iptables -A FORWARD -d ${CONTAINER_GATEWAY} -j ACCEPT

# Bring background jobs to foreground
fg %1
