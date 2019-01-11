#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

[ -n "$BTRFS_PROGS_SRC" ] && export PATH="${PATH}:${BTRFS_PROGS_SRC}"

modprobe zram num_devices="2" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable

echo "1G" > /sys/block/zram0/disksize \ || _fatal "failed to set disksize"
mkfs.btrfs /dev/zram0 || _fatal "mkfs failed"
echo "1G" > /sys/block/zram1/disksize \ || _fatal "failed to set disksize"
mkfs.btrfs /dev/zram1 || _fatal "mkfs failed"

mkdir /mnt/
mount /dev/zram0 /mnt/ || _fatal "mount failed"
mkdir /mnt/ddiss-not-a-mount
mkdir /mnt/ddiss
mount /dev/zram1 /mnt/ddiss || _fatal "mount failed"

echo data > /mnt/ddiss/data
btrfs subvolume snapshot -r /mnt/ddiss/ /mnt/ddiss/snap
btrfs send /mnt/ddiss/snap \
	| strace -o /recv.strace \
		btrfs receive /mnt/ddiss-not-a-mount/ \
	|| echo "btrfs receive /mnt/ddiss-not-a-mount/ failed."
set +x
echo "strace at /recv.strace"
