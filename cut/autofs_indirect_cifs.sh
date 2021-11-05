#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/autofs_indirect_cifs.sh" "$@"
_rt_require_networking
_rt_require_autofs

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df \
		   mount.cifs ip ping getfacl setfacl truncate du \
		   which touch cut chmod true false unlink id \
		   getfattr setfattr chacl attr killall sync strace \
		   dirname seq basename fstrim chattr lsattr stat
		   $AUTOFS_BINS" \
	--add-drivers "cifs ccm gcm ctr autofs4" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
