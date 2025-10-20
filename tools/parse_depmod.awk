#!/bin/awk -f
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.
BEGIN {
	if (ARGC < 2) {
		printf("usage: parse_depmod.awk -- <kmod> ...\n") > "/dev/stderr"
		exit 1
	}
	for (i = 1; i < ARGC; i++) {
		#printf("searching for %s\n", ARGV[i])
		search[i] = ARGV[i]
		delete ARGV[i]
	}
	search_len = ARGC - 1
	#printf("searching for %d module(s)\n", search_len)
}

# parse kmod deps into an associative array with module name as key e.g.
# "kernel/fs/btrfs/btrfs.ko: kernel/crypto/xor.ko ..."
# all_mods[btrfs] = "kernel/fs/btrfs/btrfs.ko: kernel/crypto/xor.ko ..."
# TODO: support xz, gz, etc. Currently only supports zst or uncompressed kmods
$1 ~ /^kernel.*:$/ {
	line = $0
	# grab the last component of the key
	num = split($1, a ,"/")
	key_mod = a[num]	# btrfs.ko or btrfs.zst:
	gsub(/.ko:$|.ko.zst:$/, "", key_mod) # btrfs
	all_mods[key_mod] = line	# faster if we only split() for search items
}

END {
	for (i = 1; i <= search_len; i++) {
		key = search[i]
		if (!(key in all_mods)) {
			printf("%s missing from depmod\n", key) > "/dev/stderr"
			exit 1
		}
		#printf("got %s\n", all_mods[key])
		num_deps = split(all_mods[key], this_deps, " ")
		found_dep = this_deps[1]
		gsub(/:$/, "", found_dep)
		if (found_dep in deps_paths) {
			#printf("%s already found\n", found_dep)
			continue
		}
		deps_paths[found_dep] = key
		for (newdep = 2; newdep <= num_deps; newdep++) {
			search_len++
			num=split(this_deps[newdep], a ,"/")
			key_mod = a[num]
			gsub(/.ko$|.ko.zst$/, "", key_mod)
			#printf("new dep %s\n", key_mod);
			search[search_len] = key_mod
		}
	}

	for (found in deps_paths) {
		print(found)
	}
}
