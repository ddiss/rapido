#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017, all rights reserved.
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

RAPIDO_DIR="$(realpath -e ${0%/*})"
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args
_rt_require_ceph

function _make()
{
	local make_cmd="$1"
	local src_dir="$2"
	local dst_dir="$3"

	cd ${src_dir} || _fail "bad install source at $src_dir"
	DESTDIR=${dst_dir} make "$make_cmd" \
		|| _fail "make install failed at $src_dir"
}

py_root="${RAPIDO_DIR}/initrds/pyroot"

[ -z "$CEPH_SRC" ] && _fail "$0 requires CEPH_SRC"

# XXX normally rapido doesn't get involved in the build, but the Ceph
# python scripts unfortunately need to be make installed.
if [ -f "${CEPH_SRC}/build/CMakeCache.txt" ]; then
	_make "install" "${CEPH_SRC}/build/src/ceph-disk/" "$py_root"
	_make "install" "${CEPH_SRC}/build/src/ceph-detect-init/" "$py_root"
else
	_make "ceph-disk-install-data" "${CEPH_SRC}/src" "$py_root"
	_make "ceph-detect-init-install-data" "${CEPH_SRC}/src" "$py_root"
fi

# if preparing a disk as a new OSD, a bootstrap key should be present
# ceph auth add client.bootstrap-osd mon 'allow profile bootstrap-osd'
# ceph auth list -o keyring.new && mv keyring.new keyring
$CEPH_BIN auth print-key client.bootstrap-osd \
	|| _fail "client.bootstrap-osd key not present in keyring"

dracut  --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.xfs python parted partprobe sgdisk hdparm \
		   timeout useradd id chown chmod env killall getopt basename \
		   /etc/login.defs su /etc/SuSE-release python" \
	--include "${py_root}/usr/lib/python2.7/site-packages/" \
		  "/usr/lib/python2.7/site-packages/" \
	--include "${py_root}/usr/sbin/ceph-disk" "/usr/sbin/ceph-disk" \
	--include "${py_root}/usr/bin/ceph-detect-init" \
		  "/usr/bin/ceph-detect-init" \
	--include "$RBD_NAMER_BIN" "/usr/bin/ceph-rbdnamer" \
	--include "$RBD_UDEV_RULES" "/usr/lib/udev/rules.d/50-rbd.rules" \
	--include "$CEPH_UDEV_RULES" "/usr/lib/udev/rules.d/95-ceph-osd.rules" \
	--include "$CEPH_DISK_SYSTEMD_SVC" \
		  "/usr/lib/systemd/system/ceph-disk@.service" \
	--include "$CEPH_OSD_SYSTEMD_SVC" \
		  "/usr/lib/systemd/system/ceph-osd@.service" \
	--include "$RAPIDO_DIR/ceph_osd_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--add-drivers "dm-flakey" \
	--modules "bash base network ifcfg systemd systemd-initrd dracut-systemd" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT \
	|| _fail "dracut failed"

# $qemu_cut_args are added to qemu-kvm immediately after -append, so kernel
# parameters can be specified, before any -<option> switch
qemu_cut_args="-fsdev local,id=exp1,path=${CEPH_SRC},security_model=passthrough \
	       -device virtio-9p-pci,fsdev=exp1,mount_tag=ceph_src \
	       -fsdev local,id=exp2,path=/usr/lib64,security_model=passthrough \
	       -device virtio-9p-pci,fsdev=exp2,mount_tag=usr_lib64 \
	       -fsdev local,id=exp3,path=/usr/lib,security_model=passthrough \
	       -device virtio-9p-pci,fsdev=exp3,mount_tag=usr_lib \
	       -fsdev local,id=exp4,path=/lib64,security_model=passthrough \
	       -device virtio-9p-pci,fsdev=exp4,mount_tag=lib64"
_rt_xattr_qemu_args_set "$DRACUT_OUT" "$qemu_cut_args"
# assign more memory
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
