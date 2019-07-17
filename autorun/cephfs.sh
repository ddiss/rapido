#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.
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
. /vm_ceph.env || _fatal

set -x

_vm_ar_dyn_debug_enable

cat >>/etc/passwd << EOF
ddiss:x:1000:100:David:/var/lib/nobody:/bin/bash
EOF

mkdir -p /mnt/cephfs
mount -t ceph ${CEPH_MON_ADDRESS_V1}:/ /mnt/cephfs \
	-o name=${CEPH_USER},secret=${CEPH_USER_KEY} || _fatal
cd /mnt/cephfs || _fatal

echo "precious data" > data
chown 0:0 data || _fatal
chmod 600 data || _fatal
setfacl -m g:486:r data

echo "no access via sup gid, should fail..."
/ksudo 1000:100 cat data
echo "permitted via sup gid, should pass..."
/ksudo 1000:100:486 cat data

set +x
