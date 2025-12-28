package main

import (
	"path/filepath"
	"runtime"
)

func hostOrenArch() string {
	// Normalize Go arch strings to Oren compiler arch flags.
	switch runtime.GOARCH {
	case "arm64":
		return "arm64"
	case "amd64":
		return "x64"
	default:
		return runtime.GOARCH
	}
}

func targetsOutPath(target, arch, backend, name string) string {
	// Repo-local canonical output layout:
	//   build/targets/<arch>-<os>/<backend>/<name>           for native/c
	//   build/targets/avm/bytecode/<name>.obc               for bytecode
	if backend == "bytecode" {
		return filepath.Join("build", "targets", "avm", "bytecode", name+".obc")
	}
	return filepath.Join("build", "targets", arch+"-"+target, backend, name)
}

func targetsMetaPath(target, arch, name string) string {
	// Canonical meta output layout:
	//   build/targets/<arch>-<os>/meta/<name>.meta.json
	return filepath.Join("build", "targets", arch+"-"+target, "meta", name+".meta.json")
}
