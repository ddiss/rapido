#!/bin/bash
#
# Copyright (C) SUSE LLC 2019, all rights reserved.
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

_vm_ar_dyn_debug_enable

sed -i "s#keyring = .*#keyring = /etc/ceph/keyring#g; \
	s#admin socket = .*##g; \
	s#run dir = .*#run dir = /var/run/#g; \
	s#log file = .*#log file = /var/log/\$name.\$pid.log#g" \
	/etc/ceph/ceph.conf

set -x

cd ${CEPH_SRC}/src/ceph-volume || _fatal
python3 ./setup.py build || _fatal
python3 ./setup.py install || _fatal
cd

# sshd runs as the sshd user
xid="2000"
for ug in nobody sshd; do
	echo "${ug}:x:${xid}:${xid}:${ug} user:/:/sbin/nologin" >> /etc/passwd
	echo "${ug}:x:${xid}:" >> /etc/group
	((xid++))
done

mkdir -p /etc/ssh /var/lib/empty
cat >/etc/ssh/sshd_config <<EOF
PermitRootLogin yes
AuthorizedKeysFile      $SSH_AUTHORIZED_KEY
UsePAM no
X11Forwarding no
# XXX needed for orchistrator?
Subsystem       sftp    /usr/lib/ssh/sftp-server
AcceptEnv LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
AcceptEnv LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT
AcceptEnv LC_IDENTIFICATION LC_ALL
EOF

export PATH="${PATH}:${CEPH_SRC}/build/bin/"

# provision a couple of ramdisks for OSD usage
zram_count=2
zram_size="8G"
modprobe zram num_devices="${zram_count}" || _fatal "failed to load zram module"
for i in $(seq 0 $((zram_count - 1))); do
	echo "$zram_size" > /sys/block/zram${i}/disksize \
		|| _fatal "failed to set zram disksize"
done

ssh-keygen -A || _fatal
/usr/sbin/sshd

set +x
