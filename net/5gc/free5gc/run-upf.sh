#!/bin/bash
# The UPF's TUN device carries the UE pool 10.60.0.0/16; N6 goes out through NAT.
set -e
ip tuntap add name ogstun mode tun 2>/dev/null || true
ip addr add 10.60.0.1/16 dev ogstun 2>/dev/null || true
ip link set ogstun up
iptables -t nat -A POSTROUTING -s 10.60.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || true
exec /opt/open5gs/bin/open5gs-upfd -c /rtn/upf.yaml
