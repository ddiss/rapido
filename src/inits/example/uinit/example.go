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

package main

import (
        "log"
        "fmt"
	"io/ioutil"
	"os"
	"os/exec"

	"github.com/u-root/u-root/pkg/kmodule"
	"github.com/u-root/u-root/pkg/mount"
)

func main() {
	err := kmodule.Probe("lzo", "")
	if err != nil {
		log.Fatalf("failed to load lzo kmod: %v", err)
	}
	err = kmodule.Probe("zram", "num_devices=1")
	if err != nil {
		log.Fatalf("failed to load zram kmod: %v", err)
	}

	err = ioutil.WriteFile("/sys/block/zram0/disksize", []byte("100M"),
			       0644)
	if err != nil {
		log.Fatalf("failed to write zram0 disksize: %v", err)
	}

	cmd := exec.Command("mkfs.xfs", "/dev/zram0")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	if err != nil {
		log.Fatalf("mkfs failed: %v", err)
	}

	err = mount.Mount("/dev/zram0", "/root", "xfs", "", 0)
	if err != nil {
		log.Fatalf("mount failed: %v", err)
	}

        fmt.Printf("\nRapido scratch VM running. Have a lot of fun...\n")
}
