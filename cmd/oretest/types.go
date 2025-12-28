package main

import "time"

type fixtureCase struct {
	name    string
	cmd     string
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
