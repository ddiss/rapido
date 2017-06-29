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

set -x

# add ceph account
echo "ceph:x:64045:64045:Ceph user:/:/sbin/nologin" >> /etc/passwd
echo "ceph:x:64045:" >> /etc/group
# needed for ceph-osd resolution. no idea why dracut doesn't add it
echo "root:x:0:" >> /etc/group

# systemd should have already started udevd
ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| _fatal

# send udevd a HUP to pick up the new ceph user/group
killall -HUP /usr/lib/systemd/systemd-udevd

# enable debugfs
cat /proc/mounts | grep debugfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t debugfs debugfs /sys/kernel/debug/
fi

for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done

mkdir /9p || _fatal

# /usr/lib[64] and /lib64 is exported via 9p
mkdir /9p/usr-lib64 || _fatal
mount -t 9p -o trans=virtio usr_lib64 /9p/usr-lib64 || _fatal
mkdir /9p/usr-lib || _fatal
mount -t 9p -o trans=virtio usr_lib /9p/usr-lib || _fatal
mkdir /9p/lib64 || _fatal
mount -t 9p -o trans=virtio lib64 /9p/lib64 || _fatal

# Ceph source is exported via 9p - mount it
mkdir /ceph
mount -t 9p -o trans=virtio ceph_src /ceph || _fatal

mkdir /etc/sysconfig || _fatal
mkdir /etc/ceph || _fatal
mkdir -p /var/log/ceph || _fatal
mkdir -p /var/lib/ceph/osd || _fatal
mkdir -p /var/lib/ceph/tmp/ || _fatal
mkdir -p /usr/lib/ceph/ || _fatal
# systemd service uses a hardcoded ceph-osd path
ln -sT /ceph/src/ceph-osd /usr/bin/ceph-osd || _fatal

cat << EOF > /etc/sysconfig/ceph
#PYTHONHOME=/9p/usr-lib64/python2.7/
PYTHONPATH=/ceph/src/pybind:/9p/usr-lib64/python2.7/:/9p/usr-lib/python2.7/site-packages/:/9p/usr-lib64/python2.7/lib-dynload/:/usr/lib/python2.7/site-packages/
LD_LIBRARY_PATH=/9p/usr-lib64:/9p/usr-lib:/9p/lib64:/ceph/src/.libs/
PATH=$PATH:/ceph/src/
EOF

# setup environment for cli
. /etc/sysconfig/ceph
#export PYTHONHOME
export PYTHONPATH
export LD_LIBRARY_PATH
export PATH

# use same env for systemd. ceph-osd@ is already configured with EnvironmentFile
echo "EnvironmentFile=/etc/sysconfig/ceph" \
	>> /usr/lib/systemd/system/ceph-disk@.service

cd /

# ceph-osd-prestart.sh path is hardcoded in the systemd service file
#cp /ceph/src/ceph-osd-prestart.sh /usr/lib/ceph/ceph-osd-prestart.sh || _fatal
echo "#!/bin/bash" > /usr/lib/ceph/ceph-osd-prestart.sh || _fatal
chmod 755 /usr/lib/ceph/ceph-osd-prestart.sh || _fatal

# would need /usr/bin/ceph-crush-location if osd_crush_update_on_start were set



# drop (hypervisor) admin socket paths from ceph.conf to go via network
# and use 9p keyring path
cat /ceph/src/ceph.conf \
	| sed "s#admin socket = .*##; \
	       s#heartbeat file = .*##; \
	       s#run dir = .*#run dir = /var/lib/ceph/#; \
	       s#log file = .*#log file = /var/log/ceph/\$name.log#; \
	       s#pid file = .*#pid file = /var/log/ceph/\$name.pid#; \
	       s#osd data = .*#osd data = /var/lib/ceph/osd/ceph-\$id#; \
	       s#osd journal = .*#osd journal = /var/lib/ceph/osd/ceph-\$id/journal#; \
	       s#keyring = .*#keyring = /ceph/src/keyring#; \
	       s#osd class dir = .*#osd class dir = /ceph/src/.libs#; \
	       s#erasure code dir = .*#erasure code dir = /ceph/src/.libs#; \
	       s#plugin dir = .*#plugin dir = /ceph/src/.libs#" > /etc/ceph/ceph.conf

# need to move the keyring to ceph-disk default location for new OSD
mkdir -p /var/lib/ceph/bootstrap-osd/
cp /ceph/src/keyring /var/lib/ceph/bootstrap-osd/ceph.keyring || _fatal

# systemd service runs as ceph, so need to set ownership accordingly
chown -R ceph:ceph /var/lib/ceph/ || _fatal
chown -R ceph:ceph /var/log/ceph/ || _fatal

# trigger udev, to populate /dev/disk/* and potentially activate ceph disks
udevadm trigger

ceph status || _fatal

set +x
