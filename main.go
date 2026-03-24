package main

import (
	"os"

	"github.com/igorsheg/nts/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
