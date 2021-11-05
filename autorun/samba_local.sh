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

_vm_ar_env_check || exit 1

set -x

filesystem="btrfs"

# use a non-configurable UID/GID for now
cifs_xid="579120"
echo "${CIFS_USER}:x:${cifs_xid}:${cifs_xid}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${cifs_xid}:" >> /etc/group

modprobe zram num_devices="1" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

mkfs.${filesystem} /dev/zram0 || _fatal "mkfs failed"

mkdir -p /mnt/
mount -t $filesystem /dev/zram0 /mnt/ || _fatal
chmod 777 /mnt/ || _fatal

[ -n "$SAMBA_SRC" ] && export PATH="${SAMBA_SRC}/bin/:${PATH}"

cfg_file="/smb.conf"
smb_conf_vfs=""
if [ "$filesystem" == "btrfs" ]; then
	smb_conf_vfs='vfs objects = btrfs'
fi

cat > "$cfg_file" << EOF
[global]
	workgroup = MYGROUP
	load printers = no
	smbd: backgroundqueue = no

[${CIFS_SHARE}]
	path = /mnt
	$smb_conf_vfs
	read only = no
	store dos attributes = yes
EOF

log_base=$(smbd -b -s "$cfg_file" | awk '/LOGFILEBASE:/ { print $2 }')
cfg_dirs=$(smbd -b -s "$cfg_file" | awk '/DIR:/ { printf "%s ",$2 }')
mkdir -p "$log_base" $cfg_dirs

[ -n "$SAMBA_SRC" ] \
	&& ln -s ${SAMBA_SRC}/bin/modules/vfs/ \
	   $(smbd -b -s "$cfg_file" | awk '/MODULESDIR:/ {printf "%s/vfs", $2}')

smbd -s "$cfg_file" || _fatal

set +x

echo -e "${CIFS_PW}\n${CIFS_PW}\n" \
	| smbpasswd -c "$cfg_file" -a $CIFS_USER -s || _fatal

ip link show eth0 | grep $MAC_ADDR1 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${IP_ADDR1}/${CIFS_SHARE}/"
fi
ip link show eth0 | grep $MAC_ADDR2 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${IP_ADDR2}/${CIFS_SHARE}/"
fi
echo "Log at: ${log_base}/log.smbd"
