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
	"strconv"
	"syscall"
)

type Resources struct {
	// Whether the VM should be connected to the Rapido bridge network
	Network bool
	// Number of SMP virtual CPUs to assign to the VM (QEMU uses a single
	// vCPU by default).
	CPUs uint8
	// Amount of memory to assign to the VM (use QEMU default when not set).
	// This value is MiB by default, but can be specified with an explicit
	// M or G suffix
	Memory string
}

func (resc *Resources) Apply(imgPath string) error {
	var err error

	if !resc.Network {
		// Rapido's vm.sh currently assumes network unless the
		// vm_networkless xattr is explicitly provided.
		err = syscall.Setxattr(imgPath, "user.rapido.vm_networkless",
				       []byte("1"), 0)
		if err != nil {
			return err
		}
	}

	var xattrVal string = ""
	if resc.CPUs > 1 {
		nCPUs := strconv.FormatUint(uint64(resc.CPUs), 10)
		xattrVal += " -smp cpus=" + nCPUs
	}

	if len(resc.Memory) > 0 {
		// rely on QEMU validation
		xattrVal += " -m " + resc.Memory
	}

	if len(xattrVal) > 0 {
		err = syscall.Setxattr(imgPath, "user.rapido.vm_resources",
				       []byte(xattrVal), 0)
		if err != nil {
			return err
		}
	}

	return nil
}
