#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

br_name=""
tap_pfx="rapido-tap"

_usage() {
	cat <<EOF
Error: $1

Usage: ${0##*/} [OPTIONS]

OPTIONS:
  -p <tap-prefix>:  prefix for bridged tap devices (default: $tap_pfx)
  -b <bridge-name>: name of bridge device (default: rapido.conf BR_DEV)
EOF
	exit 1
}

while getopts "p:b:" option; do
	case $option in
	p)
		tap_pfx="$OPTARG"
		;;
	b)
		br_name="$OPTARG"
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

_tap_down_callback() {
	#rapido-tap1: tap
	[[ $2 =~ ^(${tap_pfx}[0-9]+)(: tap) ]] || return
	local this_tap="${BASH_REMATCH[1]}"

	echo "+ bringing down $this_tap"
	ip link set dev "$this_tap" down || exit 1
}

_tap_rm_callback() {
	#rapido-tap1: tap
	[[ $2 =~ ^(${tap_pfx}[0-9]+)(: tap) ]] || return
	local this_tap="${BASH_REMATCH[1]}"

	echo "+ removing $this_tap"
	ip link set "$this_tap" nomaster || exit 1
	ip tuntap delete dev "$this_tap" mode tap || exit 1
}

if [ -n "$BR_DHCP_SRV_RANGE" ]; then
	# FIXME should be able to use /var/run/rapido-dnsmasq-$$.pid
	dnsmasq_pid=`ps -eo pid,args | grep -v grep | grep dnsmasq \
			| grep -- --interface=$br_name \
			| grep -- --dhcp-range=$BR_DHCP_SRV_RANGE \
			| awk '{print $1}'`
	if [ -z "$dnsmasq_pid" ]; then
		echo "failed to find dnsmasq process"
		#exit 1
	else
		echo "+ stopping dnsmasq with pid: $dnsmasq_pid"
		kill "$dnsmasq_pid"
	fi
fi

ip tuntap list | mapfile -t -C _tap_down_callback -c 1 \
	|| _fail "failed to bring down $tap_pfx devices"

echo "+ bringing down $br_name"
ip link set dev "$br_name" down || _fail "failed to bring down $br_name"

ip tuntap list | mapfile -t -C _tap_rm_callback -c 1 \
	|| _fail "failed to remove $tap_pfx devices"

echo "+ removing $br_name"
ip link delete $br_name type bridge || _fail "failed to remove $br_name"
