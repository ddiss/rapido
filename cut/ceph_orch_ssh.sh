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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args
_rt_require_lib "libexpat.so.1 libffi.so.7"
_rt_require_conf_dir CEPH_SRC	# ensure that we're deploying ceph from source
_rt_require_ceph

[ -n "$SSH_AUTHORIZED_KEY" ] || _fail "SSH_AUTHORIZED_KEY not set"
[ -f "$SSH_AUTHORIZED_KEY" ] || _fail "$SSH_AUTHORIZED_KEY not a file"

py3_rpms="python3 python3-base python3-setuptools"
py3_files="$(rpm -ql $py3_rpms)" || _fail "missing python3 rpm(s) in: $py3_rpms"
# filter out unneeded pyc & doc files
py3_files=$(echo "$py3_files" | grep -v -e "\.pyc$" -e "/doc/")


"$DRACUT" \
	--install "grep seq ps dd ip ping $py3_files \
		   lsblk lvs pvs pvchange pvremove \
		   sshd ssh-keygen /usr/lib/ssh/sftp-server \
		   $SSH_AUTHORIZED_KEY \
		   $LIBS_INSTALL_LIST \
		   ${CEPH_SRC}/build/bin/ceph \
		   ${CEPH_SRC}/build/bin/ceph-authtool \
		   ${CEPH_SRC}/build/bin/ceph-conf \
		   ${CEPH_SRC}/build/bin/ceph-mds \
		   ${CEPH_SRC}/build/bin/ceph-mgr \
		   ${CEPH_SRC}/build/bin/ceph-mon \
		   ${CEPH_SRC}/build/bin/ceph-osd" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "${CEPH_SRC}/src/ceph-volume" \
		  "${CEPH_SRC}/src/ceph-volume" \
	--include "${RAPIDO_DIR}/autorun/ceph_orch_ssh.sh" "/.profile" \
	--include "${RAPIDO_DIR}/rapido.conf" "/rapido.conf" \
	--include "${RAPIDO_DIR}/vm_autorun.env" "/vm_autorun.env" \
	--modules "bash base" \
	--drivers "zram lzo lzo-rle" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "2048M"
