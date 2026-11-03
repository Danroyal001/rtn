#!/bin/bash
# Removes RTN's 5G test network: every rtn5g-* container and the rtn5g bridge.
for container in $(docker ps -aq --filter name=^rtn5g-); do docker rm -f "$container" >/dev/null; done
docker network rm rtn5g >/dev/null 2>&1 || true
echo "rtn5g is down"
