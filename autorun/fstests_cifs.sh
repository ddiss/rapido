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

_vm_ar_env_check || exit 1

set -x

modprobe cifs
_vm_ar_hosts_create
_vm_ar_dyn_debug_enable

[ -n "$CIFS_UTILS_SRC" ] && ln -s "${CIFS_UTILS_SRC}/mount.cifs" /sbin/

set +x
creds_path="/tmp/cifs_creds"
[ -n "$CIFS_DOMAIN" ] && echo "domain=${CIFS_DOMAIN}" >> $creds_path
[ -n "$CIFS_USER" ] && echo "username=${CIFS_USER}" >> $creds_path
[ -n "$CIFS_PW" ] && echo "password=${CIFS_PW}" >> $creds_path
mount_args="-ocredentials=${creds_path}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"
set -x

mkdir -p /mnt/test
mount -t cifs //${CIFS_SERVER}/${CIFS_SHARE} /mnt/test \
	"$mount_args" || _fatal

[ -n "${FSTESTS_SRC}" ] || _fatal "FSTESTS_SRC unset"
[ -d "${FSTESTS_SRC}" ] || _fatal "$FSTESTS_SRC missing"

cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > $cfg << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=//${CIFS_SERVER}/${CIFS_SHARE}
TEST_FS_MOUNT_OPTS="$mount_args"
FSTYP="cifs"
USE_KMEMLEAK=yes
EOF

set +x

if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	cd ${FSTESTS_SRC} || _fatal
	eval "$FSTESTS_AUTORUN_CMD"
fi
