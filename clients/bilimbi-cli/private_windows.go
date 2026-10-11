package main

import (
	"errors"
	"golang.org/x/sys/windows"
	"os"
	"strings"
)

// Windows mode bits do not restrict access. The Unix 0600 equivalent is a
// protected DACL granting only the current user full access, set before bytes
// are written and preserved by the same-directory atomic rename.
func userOnlyDescriptor() (*windows.SECURITY_DESCRIPTOR, error) {
	user, err := windows.GetCurrentProcessToken().GetTokenUser()
	if err != nil {
		return nil, err
	}
	return windows.SecurityDescriptorFromString("D:P(A;;FA;;;" + user.User.Sid.String() + ")")
}
func secureFile(file *os.File) error {
	descriptor, err := userOnlyDescriptor()
	if err != nil {
		return err
	}
	acl, _, err := descriptor.DACL()
	if err != nil {
		return err
	}
	return windows.SetNamedSecurityInfo(file.Name(), windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION, nil, nil, acl, nil)
}
func privateFile(path string, info os.FileInfo) bool {
	if !info.Mode().IsRegular() {
		return false
	}
	expected, err := userOnlyDescriptor()
	if err != nil {
		return false
	}
	actual, err := windows.GetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, windows.DACL_SECURITY_INFORMATION)
	if err != nil {
		return false
	}
	control, _, err := actual.Control()
	if err != nil || control&windows.SE_DACL_PROTECTED == 0 {
		return false
	}
	// Windows may retain AUTO_INHERITED on a now-protected DACL. Compare the
	// canonical ACE list independently of those bookkeeping control flags.
	actualText, expectedText := actual.String(), expected.String()
	actualACE, expectedACE := strings.IndexByte(actualText, '('), strings.IndexByte(expectedText, '(')
	return actualACE >= 0 && expectedACE >= 0 && actualText[actualACE:] == expectedText[expectedACE:]
}
func tryLockFile(file *os.File) (bool, error) {
	err := windows.LockFileEx(windows.Handle(file.Fd()), windows.LOCKFILE_EXCLUSIVE_LOCK|windows.LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0, &windows.Overlapped{})
	if err == nil {
		return true, nil
	}
	if errors.Is(err, windows.ERROR_LOCK_VIOLATION) {
		return false, nil
	}
	return false, err
}
func unlockFile(file *os.File) {
	_ = windows.UnlockFileEx(windows.Handle(file.Fd()), 0, 1, 0, &windows.Overlapped{})
}
