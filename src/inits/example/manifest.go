// Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
//
// This library is free software; you can redistribute it and/or modify it
// under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation; either version 2.1 of the License, or
// (at your option) version 3.
//
// This library is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.

package example

import (
	"../../pkg/rapido"
)

func init() {
	manifest := rapido.Manifest{
		Name:  "example",
		Descr: "simple annotated example",
		Init: "inits/example/uinit",
		Pkgs: []string{
			// The following pkgs aren't strictly needed, but
			// provide a nice interactive shell to play with
			// once Init has completed...
			"github.com/u-root/u-root/cmds/rush",
			"github.com/u-root/u-root/cmds/ls",
			"github.com/u-root/u-root/cmds/pwd",
			"github.com/u-root/u-root/cmds/cat",
			"github.com/u-root/u-root/cmds/modprobe",
			"github.com/u-root/u-root/cmds/dmesg",
			"github.com/u-root/u-root/cmds/mount",
			"github.com/u-root/u-root/cmds/df",
			"github.com/u-root/u-root/cmds/mkdir",
			"github.com/u-root/u-root/cmds/shutdown",
			},
		Kmods: []string{"zram", "lzo"},
		Bins:  []string{"mkfs.xfs"},
		Files: []string{},
		VMResources: rapido.Resources {
			Network: false,
			CPUs: 2,
			Memory: "512M",
		},
	}

	rapido.AddManifest(manifest)
}
