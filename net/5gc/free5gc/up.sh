#!/bin/bash
# Brings up RTN's charging test network: the free5GC v4.3.0 control plane
# (NRF, AMF, SMF, AUSF, UDM, UDR, PCF, NSSF), Open5GS's UPF and a UERANSIM gNB,
# one container each on a private bridge (10.98.0.0/24).
#
#   ./up.sh            with free5GC's own CHF at 10.98.0.18
#   RTN_CHF=1 ./up.sh  with no CHF container: RTN's CHF (rtn-chf) is started
#                      separately and registers itself with the NRF
#   ./down.sh          removes everything
#
# MongoDB (free5GC's UDR database) is published on 127.0.0.1:27118 and the
# webconsole (subscriber provisioning API) on 127.0.0.1:5001.
set -euo pipefail
cd "$(dirname "$0")"
TAG=${FREE5GC_TAG:-v4.3.0}
OPEN5GS_IMAGE=${OPEN5GS_IMAGE:-gradiant/open5gs:2.8.0}
UERANSIM_IMAGE=${UERANSIM_IMAGE:-gradiant/ueransim:3.3.0}

wait_for() { # <seconds> <description> <command...>
  local seconds=$1 what=$2; shift 2
  for _ in $(seq 1 "$seconds"); do "$@" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "timed out waiting for $what" >&2; return 1
}
nf() { # <name> <ip> [docker options...] -- runs free5GC's <name> with its config
  local name=$1 ip=$2; shift 2
  docker run -d --name "rtn5gf-$name" --network rtn5gf --ip "$ip" -e GIN_MODE=release \
    -v "$PWD/${name}cfg.yaml:/free5gc/config/${name}cfg.yaml:ro" "$@" \
    "free5gc/$name:$TAG" "./$name" -c "./config/${name}cfg.yaml" >/dev/null
}

./down.sh >/dev/null 2>&1 || true
docker network create --subnet 10.98.0.0/24 rtn5gf >/dev/null
docker run -d --name rtn5gf-mongo --network rtn5gf --ip 10.98.0.2 -p 127.0.0.1:27118:27017 mongo:7.0 >/dev/null
wait_for 60 MongoDB docker exec rtn5gf-mongo mongosh --quiet --eval 'db.runCommand({ping:1}).ok'
nf nrf 10.98.0.10
wait_for 30 "the NRF" sh -c 'docker logs rtn5gf-nrf 2>&1 | grep -qi "Binding addr"'
docker run -d --name rtn5gf-upf --network rtn5gf --ip 10.98.0.20 --user root --cap-add NET_ADMIN \
  --device /dev/net/tun -v "$PWD:/rtn:ro" --entrypoint /rtn/run-upf.sh "$OPEN5GS_IMAGE" >/dev/null
nf ausf 10.98.0.13
nf udm 10.98.0.14
nf udr 10.98.0.15
nf pcf 10.98.0.16
nf nssf 10.98.0.17
if [ -z "${RTN_CHF:-}" ]; then nf chf 10.98.0.18; fi
docker run -d --name rtn5gf-smf --network rtn5gf --ip 10.98.0.12 -e GIN_MODE=release \
  -v "$PWD/smfcfg.yaml:/free5gc/config/smfcfg.yaml:ro" -v "$PWD/uerouting.yaml:/free5gc/config/uerouting.yaml:ro" \
  "free5gc/smf:$TAG" ./smf -c ./config/smfcfg.yaml -u ./config/uerouting.yaml >/dev/null
nf amf 10.98.0.11
docker run -d --name rtn5gf-webui --network rtn5gf --ip 10.98.0.19 -p 127.0.0.1:5001:5000 -e GIN_MODE=release \
  -v "$PWD/webuicfg.yaml:/free5gc/config/webuicfg.yaml:ro" "free5gc/webui:$TAG" ./webui -c ./config/webuicfg.yaml >/dev/null
docker run -d --name rtn5gf-gnb --network rtn5gf --ip 10.98.0.30 -v "$PWD/gnb.yaml:/gnb.yaml:ro" \
  --entrypoint nr-gnb "$UERANSIM_IMAGE" -c /gnb.yaml >/dev/null
wait_for 60 "NG Setup" sh -c 'docker logs rtn5gf-gnb 2>&1 | grep -q "NG Setup procedure is successful"'
echo "rtn5gf is up: free5GC $TAG control plane, Open5GS UPF, gNB (NG Setup done)"
