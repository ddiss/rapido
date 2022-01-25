#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/openldap_direct_automount.sh" "$@"
_rt_require_networking

"$DRACUT" \
	--install "resize ps strace vim-nox11 grep ip ping ss find \
		   slapd slapadd slappasswd ldapadd ldapdelete ldapsearch \
		   /etc/openldap/schema/core.schema \
		   /etc/openldap/schema/cosine.schema \
		   /usr/share/doc/packages/autofs/autofs.schema" \
	--include "/usr/lib64/openldap" "/usr/lib64/openldap" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
