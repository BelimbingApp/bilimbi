//go:build !windows

package main

import "os"

func secureFile(file *os.File) error { return file.Chmod(0600) }
func privateFile(path string, info os.FileInfo) bool {
	return info.Mode().IsRegular() && info.Mode().Perm()&0077 == 0
}
