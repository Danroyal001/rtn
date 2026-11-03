#!/bin/bash
# Starts the Open5GS 5G core network functions in one container, in the order
# they depend on each other, and waits. The UPF's TUN device (ogstun) carries
# the UE pool 10.45.0.0/16.
set -e
ip tuntap add name ogstun mode tun 2>/dev/null || true
ip addr add 10.45.0.1/16 dev ogstun 2>/dev/null || true
ip link set ogstun up
# Let UEs reach beyond the UPF (N6) through the container network.
iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || true
B=/opt/open5gs/bin
C=/rtn/open5gs
$B/open5gs-nrfd -c $C/nrf.yaml & sleep 1
$B/open5gs-scpd -c $C/scp.yaml & sleep 1
for nf in ausf udm udr pcf nssf bsf; do $B/open5gs-${nf}d -c $C/$nf.yaml & done
sleep 1
$B/open5gs-upfd -c $C/upf.yaml & sleep 1
$B/open5gs-smfd -c $C/smf.yaml &
$B/open5gs-amfd -c $C/amf.yaml &
wait -n
echo "a network function exited" >&2
exit 1
