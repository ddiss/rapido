#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021, all rights reserved.

_vm_ar_env_check || exit 1
_vm_ar_dyn_debug_enable
_vm_ar_hosts_create

_vm_kcli_param_get "rapido.vm_num"

vm_hostname="$(cat /proc/sys/kernel/hostname)"
if [ ! -n "$vm_hostname" ] || [ "$vm_hostname" == "(none)" ]; then
	_fatal "vm${kcli_rapido_vm_num} hostname not set or invalid"
fi
vm_domain="$(cat /proc/sys/kernel/domainname)"
if [ ! -n "$vm_domain" ] || [ "$vm_domain" == "(none)" ]; then
	_fatal "Domain component for vm${kcli_rapido_vm_num} hostname missing"
fi

# TODO drop authentication if LDAP_PW isn't set.
[ -n "$LDAP_PW" ] || _fatal "rapido.conf LDAP_PW setting required"

# calculate hash of pw for slapd.conf
ldap_pw_path="/tmp/pw"
(umask 077 && echo -n "$LDAP_PW" > "$ldap_pw_path")
ldap_pw_hash="$(slappasswd -T $ldap_pw_path)" || _fatal

set -x
ldap_dc_suffix="dc=${vm_domain//\./,dc=}"

mkdir -p /etc/openldap/slapd.d /run/slapd /var/lib/ldap

cat >/etc/openldap/slapd.conf <<EOF
pidfile		/run/slapd/slapd.pid
argsfile	/run/slapd/slapd.args
logfile		/var/log/slapd.log

include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /usr/share/doc/packages/autofs/autofs.schema

moduleload back_mdb.la

database     mdb
suffix       "$ldap_dc_suffix"
rootdn       "cn=Manager,${ldap_dc_suffix}"
rootpw       $ldap_pw_hash
directory    /var/lib/ldap
index        objectClass eq
EOF

cat > /etc/openldap/ldap.conf <<EOF
URI ldap://${vm_hostname}.${vm_domain}
BASE $ldap_dc_suffix
bind_policy soft
EOF

setsid --fork slapd -d 15 2>/dev/null

echo "awaiting slapd listener on port 389..."
tout=10
while [ ! -n "$(ss --no-header -l "sport = 389")" ]; do
	sleep 1
	if [ $((tout--)) -eq 0 ]; then
		cat /var/log/slapd.log
		_fatal "slapd failed to start"
	fi
done

cat > org.ldif <<EOF
dn: $ldap_dc_suffix
objectclass: dcObject
objectclass: organization
o: Rapido Org
dc: ${vm_domain%%\.*}

dn: cn=Manager,${ldap_dc_suffix}
objectclass: organizationalRole
cn: Manager
EOF

ldapadd -y "$ldap_pw_path" -x -D "cn=Manager,${ldap_dc_suffix}" -f org.ldif \
	|| _fatal "failed to add ldif data"

# this path must exist on automount / cifs clients and carry mount credentials
cifs_creds_path="/tmp/cifs_creds"
mount_args="-fstype=cifs,credentials=${cifs_creds_path}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"

# attempt to add automount map data
cat > /automount_map.ldif <<EOF
dn: ou=admin,${ldap_dc_suffix}
ou: admin
objectClass: top
objectClass: organizationalUnit

dn: ou=automount,ou=admin,${ldap_dc_suffix}
ou: automount
objectClass: top
objectClass: organizationalUnit

dn: ou=auto.master,ou=automount,ou=admin,${ldap_dc_suffix}
ou: auto.master
objectClass: top
objectClass: automountMap

dn: cn=/-,ou=auto.master,ou=automount,ou=admin,${ldap_dc_suffix}
cn: /-
objectClass: top
objectClass: automount
automountInformation: ldap:ou=auto.direct.smb,ou=automount,ou=admin,${ldap_dc_suffix} --timeout=60 --ghost

dn: ou=auto.direct.smb,ou=automount,ou=admin,${ldap_dc_suffix}
ou: auto.direct.smb
objectClass: top
objectClass: automountMap

dn: cn=/smb/share,ou=auto.direct.smb,ou=automount,ou=admin,${ldap_dc_suffix}
cn: /smb/share
objectClass: top
objectClass: automount
automountInformation: $mount_args ://${CIFS_SERVER}/${CIFS_SHARE}
EOF

ldapadd -y "$ldap_pw_path" -x -D "cn=Manager,${ldap_dc_suffix}" \
	-f /automount_map.ldif || _fatal "failed to add ldif data"

ldapsearch -y "$ldap_pw_path" -x -D "cn=Manager,${ldap_dc_suffix}" \
	'(objectclass=*)' namingContexts || _fatal "ldapsearch failed"

set +x

echo "slapd running, with log at /var/log/slapd.log"
