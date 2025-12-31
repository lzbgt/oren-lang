package main

import "time"

type fixtureCase struct {
	name string
	// cmd is executed via `sh -c <cmd>` and logged to `log`.
	// Exactly one of cmd or run must be set.
	cmd string
	// run is used for fixtures that need structured orchestration beyond a single shell command
	// (e.g. remote x64 batch gates).
	//
	// The runner must append any output to logPath and return the final exit code (0=pass).
	run func(timeoutBin string, timeout time.Duration, logPath string) int

	timeout time.Duration
	log     string
	ok      func(rc int) bool
	cleanup []string
}

type runtimeFixtureCase struct {
	name    string
	build   string
	run     string
	log     string
	ok      func(rc int, out string) bool
	cleanup []string
}
