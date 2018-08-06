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
	"os"
	"fmt"
	"log"
	"path"
	"strings"
	"io/ioutil"
	"encoding/gob"

	// embedded vendor repo
	"../ini"
)

type RapidoConf struct {
	// rapido.conf key=val map
	f map[string]string

	// command line
	Debug bool
}

// basic support for conf variable expansion
func parseConfExpand(f map[string]string) error {
	for key, val := range f {
		// fast path if no variable to expand
		if !strings.Contains(val, "$") {
			continue
		}
		for rkey, rval := range f {
			val = strings.Replace(val, "${" + rkey + "}", rval, -1)
			val = strings.Replace(val, "$" + rkey, rval, -1)
		}
		// No support for recursive replacement or missing vars
		if strings.Contains(val, "$") {
			return fmt.Errorf("%s=%s is recursive or missing",
					  key, val)
		}
		f[key] = val
	}
	return nil
}

// Parse confPath as an ini/shell env and return the resulting RapidoConf struct
func ParseConf(confPath string, debug bool) (*RapidoConf, error) {
	// TODO set RapidoConfFile defaults
	conf := new(RapidoConf)

	cfg, err := ini.Load(confPath)
	if err != nil {
		return nil, err
	}

	// "in cases that you are very sure about only reading data through the
	// library, you can set cfg.BlockMode = false to speed up read
	// operations"
	cfg.BlockMode = false

	// the private config map is validated on demand, as component specific
	// parameters are requested via the accessor functions
	conf.f = cfg.Section(ini.DEFAULT_SECTION).KeysHash()

	// ideally NameMapper / ValueMapper could handle this in a single pass
	err = parseConfExpand(conf.f)
	if err != nil {
		return nil, err
	}

	conf.Debug = debug
	if conf.Debug {
		conf.DumpConf()
	}

	return conf, nil
}

func (conf *RapidoConf) DumpConf() {
	log.Printf("%+v\n", *conf)
}

func checkDirVal(f map[string]string, key string) (string, error) {
	val := f[key]
	if len(val) == 0 {
		return "", fmt.Errorf("%s not configured", key)
	}
	stat, err := os.Stat(val)
	if err != nil {
		return "", err
	}
	if !stat.IsDir() {
		return "", fmt.Errorf("%s is not a directory", val)
	}

	return val, nil
}

type KmodsInfo struct {
	KernelInstModPath string
	KernelVersion string
}

func (conf *RapidoConf) GetKmodsInfo() (*KmodsInfo, error) {
	kernelSrc, err := checkDirVal(conf.f, "KERNEL_SRC")
	if err != nil {
		return nil, err
	}

	kverPath := path.Join(kernelSrc, "include/config/kernel.release")
	kver, err := ioutil.ReadFile(kverPath)
	if err != nil {
		return nil, err
	}
	kernelVersion := strings.TrimSpace(string(kver))

	kernelInstModPath, err := checkDirVal(conf.f, "KERNEL_INSTALL_MOD_PATH")
	if err != nil {
		return nil, err
	}

	return &KmodsInfo{kernelInstModPath, kernelVersion}, nil
}

func (conf *RapidoConf) WriteGob(path string) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	e := gob.NewEncoder(file)

	err = e.Encode(conf.f)
	if err != nil {
		return err
	}
	// could also store runtime cut flags (-debug)
	return file.Close()
}
