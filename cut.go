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
	"flag"
	"log"
	"fmt"
	"os"
	"io/ioutil"
	"path"
	"path/filepath"

	"github.com/u-root/u-root/pkg/golang"
	"github.com/u-root/u-root/pkg/uroot"

	"./src/pkg/rapido"

	// inits registered via AddManifest() callback
	_ "./src/inits/example"
)

func listInits(title string) {
	fmt.Print(title)
	cb := func(m rapido.Manifest) {
		fmt.Printf("  %s\n\t%s\n", m.Name, m.Descr)
	}
	rapido.IterateManifests(cb)
}

func usage() {
	fmt.Printf("Usage: %s [options] <init>\n", filepath.Base(os.Args[0]))
	flag.PrintDefaults()
	listInits("Available inits:\n")
}

func cut(conf *rapido.RapidoConf, m *rapido.Manifest, rdir string,
	 imgPath string) error {
	var files []string
	var err error

	if len(m.Kmods) > 0 {
		files, err = rapido.FindKmods(conf, m.Kmods)
		if err != nil {
			return err
		}
	}

	if len(m.Bins) > 0 {
		bins, err := rapido.FindBins(m.Bins)
		if err != nil {
			return err
		}
		files = append(files, bins...)
	}

	if len(m.Files) > 0 {
		files = append(files, m.Files...)
	}

	// u-root's base "init" is responsible for invoking the manifest
	// specific "uinit", and subsequently interactive shell (rush)
	pkgs := append(m.Pkgs, "github.com/u-root/u-root/cmds/init", m.Init)

	env := golang.Default()
	env.CgoEnabled = false

	// add rapido directory as part of GOPATH, this allows the manifest to
	// specify pkg/Init paths as relative to rapido source.
	env.GOPATH += ":" + rdir

	// TODO support "source" mode
	builder, err := uroot.GetBuilder("bb")
	if err != nil {
		return err
	}

	archiver, err := uroot.GetArchiver("cpio")
	if err != nil {
		return err
	}

	tmpDir, err := ioutil.TempDir("", "rapido")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)

	// XXX write a subset of conf based on manifest?
	confGobPath := path.Join(tmpDir, "rapido.conf.bin")
	err = conf.WriteGob(confGobPath)
	if err != nil {
		return err
	}

	files = append(files, confGobPath + ":rapido.conf.bin")

	// XXX OpenWriter truncates to zero, but the resource xattrs need to be
	// dropped, so delete unconditionally
	err = os.Remove(imgPath)
	if err != nil && !os.IsNotExist(err) {
		return err
	}

	w, err := archiver.OpenWriter(imgPath, "", "")
	if err != nil {
		return err
	}

	opts := uroot.Opts{
		TempDir: tmpDir,
		Env:     env,
		Commands: []uroot.Commands{
			{
				Builder:  builder,
				Packages: pkgs,
			},
		},
		Archiver:     archiver,
		ExtraFiles:   files,
		OutputFile:   w,
		InitCmd:      "init",
		DefaultShell: "/bbin/rush",
	}

	if conf.Debug {
		log.Printf("uroot opts: %+v\n", opts)
	}

	err = uroot.CreateInitramfs(opts)
	if err != nil {
		return err
	}

	return nil
}

type cliParams struct {
	list bool
	debug bool
	confPath string
	imgPath string
}

func main() {
	// XXX: binary is under /tmp/go-build when run via "go run"!
	rdir, err := filepath.Abs(filepath.Dir(os.Args[0]))
	if err != nil {
		log.Fatalf("failed to determine rapido dir: %v", err)
	}

	params := new(cliParams)
	flag.Usage = usage
	flag.BoolVar(&params.list, "list", false, "list available inits")
	flag.BoolVar(&params.debug, "debug", false, "log debug messages")
	flag.StringVar(&params.confPath, "conf", path.Join(rdir, "rapido.conf"),
		       "rapido.conf path")
	flag.StringVar(&params.imgPath, "img",
		       path.Join(rdir, "imgs", "rapido-img.cpio"),
		       "initramfs image path")

	flag.Parse()

	if params.list {
		listInits("Available inits:\n")
		return
	}

	// currently only a single manifest is supported.
	if len(flag.Args()) != 1 {
		usage()
		return
	}

	initName := flag.Arg(0)
	m := rapido.LookupManifest(initName)
	if m == nil {
		fmt.Printf("Failed to lookup manifest: %s\n", initName)
		usage()
		return
	}

	conf, err := rapido.ParseConf(params.confPath, params.debug)
	if err != nil {
		log.Fatalf("failed to parse config: %v", err)
	}

	err = cut(conf, m, rdir, params.imgPath)
	if err != nil {
		log.Fatalf("failed cut image: %v", err)
	}

	err = m.VMResources.Apply(params.imgPath)
	if err != nil {
		log.Fatalf("failed to apply VM resources: %v", err)
	}
}
