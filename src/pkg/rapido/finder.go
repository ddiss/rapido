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
	"strings"
	"os"
	"os/exec"
	"path"
	"path/filepath"

	"github.com/u-root/u-root/pkg/kmodule"
)

func FindKmods(conf *RapidoConf, kmodNames []string) ([]string, error) {
	paths := make(map[string]string)

	kmodsInfo, err := conf.GetKmodsInfo()
	if err != nil {
		return nil, err
	}

	opts := kmodule.ProbeOpts{
                RootDir:  kmodsInfo.KernelInstModPath,
                KVer:     kmodsInfo.KernelVersion,
                DryRunCB: func(modPath string) {
			// strip local install base path for dstPath
			p := strings.Split(modPath,
					   kmodsInfo.KernelInstModPath + "/")
			if len(p) != 2 {
				return
			}
			// local_src=img_dest. Stage in map to weed out dups.
			paths[modPath] = p[1]
                },
        }

	for _, name := range kmodNames {
		err = kmodule.ProbeOptions(name, "", opts)
		if err != nil {
			return nil, err
		}
	}

	var absPaths []string
	for src, dst := range paths {
		absPaths = append(absPaths, src + ":" + dst)
	}

	// append modules.dep, needed by modprobe
	relModuleDep := path.Join("lib/modules/", kmodsInfo.KernelVersion,
				  "modules.dep")
	absPaths = append(absPaths,
			  path.Join(kmodsInfo.KernelInstModPath,
				    relModuleDep) + ":" + relModuleDep)

	return absPaths, nil
}

func FindBins(binNames []string) ([]string, error) {
	pathOld := os.Getenv("PATH")
	err := os.Setenv("PATH", pathOld + ":/usr/sbin:/sbin")
	if err != nil {
		return nil, err
	}
	defer os.Setenv("PATH", pathOld)

	var absPaths []string
	for _, name := range binNames {
		f, err := exec.LookPath(name)
		if err != nil {
			return nil, err
		}
		f, err = filepath.Abs(f)
		if err != nil {
			return nil, err
		}
		absPaths = append(absPaths, f)
	}

	return absPaths, nil
}
