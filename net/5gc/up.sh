#!/bin/bash
# Brings up RTN's 5G test network: MongoDB, the Open5GS 5G core and a UERANSIM
# gNB. All three share one network namespace on a private bridge (10.99.0.10),
# so the stock loopback addresses in the Open5GS configs work. UEs run in their
# own namespaces (ue.sh), so their traffic really crosses the radio link
# simulation, GTP-U and the UPF.
#
#   ./up.sh     start (a network that is already up is left alone)
#   ./down.sh   remove every container and the bridge
#
# MongoDB, the core's subscriber database, is published on 127.0.0.1:27117.
set -euo pipefail
cd "$(dirname "$0")"
OPEN5GS_IMAGE=${OPEN5GS_IMAGE:-gradiant/open5gs:2.8.0}
UERANSIM_IMAGE=${UERANSIM_IMAGE:-gradiant/ueransim:3.3.0}
MONGO_IMAGE=${MONGO_IMAGE:-mongo:7.0}

wait_for() { # <seconds> <description> <command...>
  local seconds=$1 what=$2; shift 2
  for _ in $(seq 1 "$seconds"); do "$@" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "timed out waiting for $what" >&2; return 1
}

if [ "$(docker inspect -f '{{.State.Running}}' rtn5g-gnb 2>/dev/null)" = true ]; then
  echo "rtn5g is already up"; exit 0
fi
./down.sh >/dev/null 2>&1 || true
docker network create --subnet 10.99.0.0/24 rtn5g >/dev/null
docker run -d --name rtn5g-mongo --network rtn5g --ip 10.99.0.10 \
  -p 127.0.0.1:27117:27017 "$MONGO_IMAGE" >/dev/null
wait_for 60 MongoDB docker exec rtn5g-mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok'
docker run -d --name rtn5g-core --network container:rtn5g-mongo --user root \
  --cap-add NET_ADMIN --device /dev/net/tun -e DB_URI=mongodb://127.0.0.1/open5gs \
  -v "$PWD:/rtn:ro" --entrypoint /rtn/open5gs/run-core.sh "$OPEN5GS_IMAGE" >/dev/null
wait_for 60 "the AMF" sh -c 'docker logs rtn5g-core 2>&1 | grep -q "AMF initialize...done"'
docker run -d --name rtn5g-gnb --network container:rtn5g-mongo \
  -v "$PWD/ueransim:/cfg:ro" --entrypoint nr-gnb "$UERANSIM_IMAGE" -c /cfg/gnb.yaml >/dev/null
wait_for 60 "NG Setup" sh -c 'docker logs rtn5g-gnb 2>&1 | grep -q "NG Setup procedure is successful"'
echo "rtn5g is up: Open5GS core, gNB (NG Setup done), MongoDB on 127.0.0.1:27117"
