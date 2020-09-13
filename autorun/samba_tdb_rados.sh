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

_vm_ar_env_check || exit 1

set -x

export PATH="${SAMBA_SRC}/bin/:${PATH}"

# use a uid and gid which match the CephFS root owner, so SMB users can perform
# I/O without needing to chmod. nobody is needed for guest DCERPC.
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_UID-0}:${CEPH_ROOT_INO_GID-0}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "nobody:x:65534:65534:nobody:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_GID-0}:" >> /etc/group
echo "nobody:x:65534" >> /etc/group

# dcerpc server does getaddrinfo during naclrpc_as_system auth
echo "$IP_ADDR1 rapido1" >> /etc/hosts
echo "$IP_ADDR2 rapido2" >> /etc/hosts

_vm_ar_dyn_debug_enable

sed -i "s#keyring = .*#keyring = /etc/ceph/keyring#g; \
	s#admin socket = .*##g; \
	s#run dir = .*#run dir = /var/run/#g; \
	s#log file = .*#log file = /var/log/\$name.\$pid.log#g" \
	/etc/ceph/ceph.conf

mkdir -p /usr/local/samba/var/run/
ln -s /usr/local/samba/var/ /var/log/samba
mkdir -p /usr/local/samba/etc/
mkdir -p /usr/local/samba/var/lock
mkdir -p /usr/local/samba/private/
mkdir -p /usr/local/samba/lib/
ln -s ${SAMBA_SRC}/bin/modules/vfs/ /usr/local/samba/lib/vfs

# use the rapido provided vm_num as Samba node identifier (VNN)
_vm_kcli_param_get "rapido.vm_num"
[ -z "$kcli_rapido_vm_num" ] && _fatal "rapido.vm_num missing in kcli"

# XXX HACK - use a separate smb.conf for tdb_radosd which doesn't enable
# clustering. This is to solve the problem of bootstrapping - the dcerpc
# server needs to be able to authenticate clients without accessing a
# (cluster provided) passdb.
cat > /usr/local/samba/etc/tdb_rados_smb.conf << EOF
[global]
	workgroup = MYGROUP
	load printers = no
	smbd: backgroundqueue = no
	# used for clustering metadata and FS (vfs_ceph)
	ceph: config_file = /etc/ceph/ceph.conf
	# used for clustering metadata and FS (vfs_ceph)
	ceph: user_id = client.${CEPH_USER}
	# pool name is used for Samba clustering metadata only
	ceph: pool_name = sambakv
	# FIXME cluster_name should default to ceph
	ceph: cluster_name = ceph

	# each Samba gw instance requires a unique static VNN
	ceph: vnn = $kcli_rapido_vm_num
	log level = 10
EOF

# append global clustering and share details for all other smb.conf consumers
cat /usr/local/samba/etc/tdb_rados_smb.conf \
	> /usr/local/samba/etc/smb.conf << EOF
	# everything except tdb_radosd should 
	clustering = yes
	clustering backend = ceph

[${CIFS_SHARE}]
	path = /
	vfs objects = ceph
	read only = no
	# no vfs_ceph flock support - "kernel" is confusing here
	kernel share modes = no
	# no vfs_ceph lease delegation support
	oplocks = no
EOF

echo "starting tdb_radosd..."
tdb_radosd -s /usr/local/samba/etc/smb.conf &
sleep 1
echo "starting rpc.tdb_rados test suite..."
#smbtorture 'ncalrpc[tdb_rados,auth_type=ncalrpc_as_system]' rpc.tdb_rados
gdb -ex "r 'ncalrpc[tdb_rados,auth_type=ncalrpc_as_system]' rpc.tdb_rados"  smbtorture
set +x
