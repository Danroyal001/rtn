#!/bin/bash
# Starts a UERANSIM UE in its own network namespace on the rtn5g bridge, and
# waits for its PDU session.
#   ./ue.sh <name> <ue.yaml>      e.g. ./ue.sh 0001 ue-0001.yaml
# `rtn 5g ue-config <msisdn>` writes the yaml for an RTN subscriber.
set -euo pipefail
name=$1; config=$(realpath "$2")
UERANSIM_IMAGE=${UERANSIM_IMAGE:-gradiant/ueransim:3.3.0}
docker rm -f "rtn5g-ue-$name" >/dev/null 2>&1 || true
docker run -d --name "rtn5g-ue-$name" --network rtn5g --cap-add NET_ADMIN \
  --device /dev/net/tun -v "$config:/ue.yaml:ro" --entrypoint nr-ue "$UERANSIM_IMAGE" \
  -c /ue.yaml >/dev/null
for _ in $(seq 1 30); do
  if docker logs "rtn5g-ue-$name" 2>&1 | grep -q 'TUN interface\[uesimtun0'; then
    docker logs "rtn5g-ue-$name" 2>&1 | grep 'TUN interface'; exit 0
  fi
  sleep 1
done
docker logs "rtn5g-ue-$name" 2>&1 | tail -20; exit 1
