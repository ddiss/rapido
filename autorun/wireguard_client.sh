#!/bin/bash
#
# Copyright (C) SUSE LLC 2020, all rights reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation; either version 2.1 of the License, or
# (at your option) version 3.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

set -x

modprobe wireguard || _fatal

_vm_ar_dyn_debug_enable

export PATH="${PATH}:${WIREGUARD_SRC}/src"

[ -n "$WIREGUARD_CLI_TUN_ADDR" ]  || _fatal
[ -n "$WIREGUARD_CLI_PRIVKEY" ]  || _fatal
[ -n "$WIREGUARD_CLI_EP_PORT" ] || _fatal
[ -n "$WIREGUARD_SRV_PUBKEY" ]  || _fatal
[ -n "$WIREGUARD_SRV_TUN_ADDR" ]  || _fatal
[ -n "$WIREGUARD_SRV_EP_IP" ] || _fatal
[ -n "$WIREGUARD_SRV_EP_PORT" ] || _fatal
ip link add dev wg0 type wireguard || _fatal
ip address add dev wg0 "$WIREGUARD_CLI_TUN_ADDR" || _fatal

cat  > /wg.conf <<EOF
[Interface]
PrivateKey = $WIREGUARD_CLI_PRIVKEY
ListenPort = $WIREGUARD_CLI_EP_PORT

[Peer]
PublicKey = $WIREGUARD_SRV_PUBKEY
Endpoint = ${WIREGUARD_SRV_EP_IP}:${WIREGUARD_SRV_EP_PORT}
AllowedIPs = $WIREGUARD_SRV_TUN_ADDR
EOF

wg setconf wg0 /wg.conf || _fatal
ip link set up dev wg0 || _fatal
wg

set +x
