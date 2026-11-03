#!/bin/bash
# Removes RTN's charging test network: every rtn5gf-* container and the bridge.
for container in $(docker ps -aq --filter name=^rtn5gf-); do docker rm -f "$container" >/dev/null; done
docker network rm rtn5gf >/dev/null 2>&1 || true
echo "rtn5gf is down"
