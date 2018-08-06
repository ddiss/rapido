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

package rapido

import (
	"fmt"
)

type Manifest struct {
	// Name of init back-end
	Name string
	// short description of what this image does
	Descr string
	// init package runs immediately following boot..
	// The stock u-root init process is responsible for invoking the "uinit"
	// provided alongside a given manifest under:
	// github.com/rapido-linux/rapido/u-root/init/<Name>/uinit/
	Init  string
	// Additional go packages to install in the initramfs
	Pkgs  []string
	// kernel modules required by this init
	// TODO use u-root/pkg/kmodule to find deps
	Kmods []string
	// Binaries to locate via PATH (and sbin). The initramfs destination
	// will match the local source, with ldd dependencies also pulled in.
	Bins []string
	// files to include in the initramfs image. ldd dependencies will be
	// automatically pulled in alongside binaries.
	// Files will be placed in the same path as the local source by default.
	// The initramfs destination path can be explicitly specified via:
	// <local source>:<initramfs dest>
	// TODO use u-root/cmds/which to locate bins under PATH (+sbin)
	Files []string

	// VMResources are different from the rest of the Manifest in that they are
	// considered at VM boot time.
	VMResources Resources
}

var (
	manifs = make(map[string]Manifest)
)

func AddManifest(m Manifest) error {
	name := m.Name
        if _, ok := manifs[name]; ok {
                return fmt.Errorf("%v manifest already present", name)
        }
	manifs[name] = m
	return nil
}

func LookupManifest(name string) *Manifest {
	if m, ok := manifs[name]; ok {
		return &m
	}
	return nil
}

func IterateManifests(cb func(m Manifest)) {
	for _, m := range manifs {
		cb(m)
	}
}
