package main

import (
	"fmt"
	"oren/internal/orenlsp"
	"os"
)

func main() {
	if err := orenlsp.NewServer(os.Stdin, os.Stdout).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "oren-lsp: %v\n", err)
		os.Exit(1)
	}
}
