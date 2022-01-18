#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# XXX we could provide host bridge/tap deployment via systemd-networkd, but it
# shouldn't be required on the host system, so use iproute2 only.
br_name=""
tap_pfx="rapido-tap"
tap_count="3"
tap_owner=""	# TODO default to env SUDO_USER?

_usage() {
	cat <<EOF
Error: $1

Usage: ${0##*/} [OPTIONS] -o tap-owner

OPTIONS:
  -o <tap-owner>:   user assigned tap device ownership (required)
  -p <tap-prefix>:  prefix for new bridged tap devices (default: $tap_pfx)
  -c <tap-count>:   number of tap devices to create (default: $tap_count)
  -b <bridge-name>: name of bridge device (default: rapido.conf BR_DEV)
  -a <bridge-addr>: IP address assigned to bridge (default: rapido.conf BR_ADDR)
EOF
	exit 1
}

while getopts "b:p:c:o:" option; do
	case $option in
	o)
		tap_owner="$OPTARG"
		;;
	p)
		tap_pfx="$OPTARG"
		;;
	c)
		tap_count="$OPTARG"
		[[ $tap_count =~ ^[0-9]+$ ]] \
			|| _usage "tap_count must be numeric"
		;;
	b)
		br_name="$OPTARG"
		;;
	a)
		br_addr="$OPTARG"
		;;
	*)
		_usage "Invalid parameter"
		;;
	esac
done

if [ -z "$br_name" ]; then
       _rt_require_conf_setting BR_DEV
       br_name="$BR_DEV"
fi
[ -z "$tap_owner" ] && _usage "-o <tap-owner> required"
[ -z "$br_addr" ] && br_addr="$BR_ADDR"

# cleanup on premature exit by executing whatever has been prepended to @unwind
unwind=""
trap "eval \$unwind" 0 1 2 3 15

ip link add "$br_name" type bridge || _fail "failed to add $br_name"
unwind="ip link delete \"$br_name\" type bridge; $unwind"
echo -n "+ created bridge \"$br_name\""
if [ -n "$br_addr" ]; then
	ip addr add "$br_addr" dev "$br_name" || exit 1
	unwind="ip addr del \"$br_addr\" dev \"$br_name\"; $unwind"
	echo -n " with address \"$br_addr\""
fi
# TODO support previous BR_IF and BR_DHCP_SRV_RANGE functionality?

if [ -n "$BR_IF" ]; then
	# TODO: make BR_IF a script parameter too?
	ip link set "$BR_IF" master "$br_name" || exit 1
	unwind="ip link set \"$BR_IF\" nomaster; $unwind"
	echo -n ", connected to \"$BR_IF\""
fi
echo

for ((i = 1; i <= $tap_count; i++)); do
	tap_dev="${tap_pfx}${i}"
	# setup tap interfaces for VMs
	ip tuntap add dev "$tap_dev" mode tap user "$tap_owner" \
		|| exit 1
	unwind="ip tuntap delete dev \"$tap_dev\" mode tap; $unwind"
	ip link set "$tap_dev" master "$br_name" || exit 1
	unwind="ip link set \"$tap_dev\" nomaster; $unwind"
	echo "+ created \"$tap_dev\""
done

ip link set dev "$br_name" up || exit 1
unwind="ip link set dev \"$br_name\" down; $unwind"

for ((i = 1; i <= $tap_count; i++)); do
	tap_dev="${tap_pfx}${i}"

	ip link set dev "$tap_dev" up || exit 1
	unwind="ip link set dev \"$tap_dev\" down; $unwind"
done

if [ -n "$BR_DHCP_SRV_RANGE" ]; then
	# TODO parse net-conf/vm static ips to create --dhcp-host= parameters?
	# TODO this needn't run as root
	dnsmasq --no-hosts --no-resolv \
		--pid-file=/var/run/rapido-dnsmasq-$$.pid \
		--bind-interfaces \
		--interface="$br_name" \
		--except-interface=lo \
		--dhcp-range="$BR_DHCP_SRV_RANGE" || exit 1
	unwind="kill $(cat /var/run/rapido-dnsmasq-$$.pid); ${unwind}"
	echo "+ started DHCP server on \"$br_name\""
fi

# success! clear unwind
unwind=""
