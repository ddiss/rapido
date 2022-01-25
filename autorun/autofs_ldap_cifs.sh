#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_vm_ar_env_check || exit 1

_vm_ar_dyn_debug_enable

modprobe autofs4

_vm_kcli_param_get "rapido.vm_num"
vm_hostname="$(cat /proc/sys/kernel/hostname)"
if [ ! -n "$vm_hostname" ] || [ "$vm_hostname" == "(none)" ]; then
	_fatal "HOSTNAME${kcli_rapido_vm_num} not set or invalid"
fi
vm_domain="$(cat /proc/sys/kernel/domainname)"
if [ ! -n "$vm_domain" ] || [ "$vm_domain" == "(none)" ]; then
	_fatal "domainname not set. Set fqdn in HOSTNAME${kcli_rapido_vm_num}"
fi

creds_path="/tmp/cifs_creds"
if [ -n "$CIFS_DOMAIN" ]; then
	[ "$CIFS_DOMAIN" == "$vm_domain" ] \
		|| _fatal "CIFS_DOMAIN and ldap domain must match"
	echo "domain=${CIFS_DOMAIN}" >> $creds_path
fi
[ -n "$CIFS_USER" ] && echo "username=${CIFS_USER}" >> $creds_path
[ -n "$CIFS_PW" ] && echo "password=${CIFS_PW}" >> $creds_path
mount_args="credentials=${creds_path}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"

# TODO drop authentication if LDAP_PW isn't set.
[ -n "$LDAP_PW" ] || _fatal "rapido.conf LDAP_PW setting required"
[ -n "$LDAP_SERVER" ] || _fatal "rapido.conf LDAP_SERVER setting required"

# calculate hash of pw for slapd.conf
ldap_pw_path="/tmp/pw"
(umask 077 && echo -n "$LDAP_PW" > "$ldap_pw_path")
#ldap_pw_hash="$(slappasswd -T $ldap_pw_path)" || _fatal

set -x
ldap_dc_suffix="dc=${vm_domain//\./,dc=}"

mkdir -p /etc/openldap/ /etc/default
cat > /etc/openldap/ldap.conf <<EOF
URI     ldap://${LDAP_SERVER}
BASE	$ldap_dc_suffix
EOF

echo "[ autofs ]" > /etc/autofs.conf

cat > /etc/default/autofs <<EOF
MASTER_MAP_NAME="ou=auto.master,ou=automount,ou=admin,${ldap_dc_suffix}"

LOGGING="verbose"

LDAP_URI="ldap://${LDAP_SERVER}"

SEARCH_BASE="ou=automount,ou=admin,${ldap_dc_suffix}"
EOF

cat > /etc/autofs_ldap_auth.conf <<EOF
<autofs_ldap_sasl_conf
        usetls="no"
        tlsrequired="no"
        authrequired="no"
/>
EOF
chmod 600 /etc/autofs_ldap_auth.conf

mkdir -p /etc/sysconfig/
touch /etc/sysconfig/autofs # avoid noise

echo "automount: files ldap" > /etc/nsswitch.conf

mkdir /smb /share

if [ -n "$AUTOFS_SRC" ]; then
	for l in /usr/lib/autofs /usr/lib64/autofs; do
		mkdir -p "$l"
		pushd "$l"
		ln -s ${AUTOFS_SRC}/lib/*.so .
		ln -s ${AUTOFS_SRC}/modules/*.so .
		# see autofs/modules/Makefile...
		ln -s "lookup_file.so" "lookup_files.so"
		popd
	done
	export PATH="${AUTOFS_SRC}/daemon:$PATH"
fi

# sanity test
ldapsearch -y "$ldap_pw_path" -x -D "cn=Manager,${ldap_dc_suffix}" \
	'(objectclass=*)' namingContexts || _fatal "ldapsearch failed"

automount --dumpmaps
setsid --fork automount --debug --foreground

set +x
