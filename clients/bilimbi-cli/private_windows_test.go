package main

import (
	"golang.org/x/sys/windows"
	"os"
	"path/filepath"
	"testing"
)

func TestWindowsFallbackRejectsEveryoneACL(t *testing.T) {
	path := filepath.Join(t.TempDir(), "credential.json")
	if err := writeJSON(path, credentials{Access: "access", Refresh: "refresh"}); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil || !privateFile(path, info) {
		t.Fatal("private Windows ACL rejected", err)
	}
	descriptor, err := windows.SecurityDescriptorFromString("D:P(A;;FA;;;WD)")
	if err != nil {
		t.Fatal(err)
	}
	acl, _, err := descriptor.DACL()
	if err != nil {
		t.Fatal(err)
	}
	if err = windows.SetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION, nil, nil, acl, nil); err != nil {
		t.Fatal(err)
	}
	if privateFile(path, info) {
		t.Fatal("everyone-readable credential accepted")
	}
}
