//go:build windows

package main

import (
	"os/exec"
)

func setProcAttr(cmd *exec.Cmd) {
	// Windows: Job Object with kill-on-close is set up separately
	// For now this is a stub — the binary is not built on windows in this spike
}

func killProcessGroup(pgid int) error {
	return nil // stub for compilation only
}

func isPidAlive(pid int) bool {
	return false // stub for compilation only
}
