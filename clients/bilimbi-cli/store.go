package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"github.com/99designs/keyring"
)

type profile struct {
	Discovery  discovery `json:"discovery"`
	Backend    string    `json:"credential_backend"`
	NeedsLogin bool      `json:"needs_login,omitempty"`
}
type profiles struct {
	Active string             `json:"active"`
	Items  map[string]profile `json:"profiles"`
}
type vault interface {
	Get(string) ([]byte, error)
	Set(string, []byte) error
	Delete(string) error
}
type nativeVault struct{ ring keyring.Keyring }

func (v nativeVault) Get(key string) ([]byte, error) {
	item, err := v.ring.Get(key)
	return item.Data, err
}
func (v nativeVault) Set(key string, data []byte) error {
	return v.ring.Set(keyring.Item{Key: key, Data: data, Label: "Bilimbi connection"})
}
func (v nativeVault) Delete(key string) error { return v.ring.Remove(key) }
func openNative() (vault, error) {
	backend := keyring.SecretServiceBackend
	switch runtime.GOOS {
	case "darwin":
		backend = keyring.KeychainBackend
	case "windows":
		backend = keyring.WinCredBackend
	}
	ring, err := keyring.Open(keyring.Config{ServiceName: "bilimbi-native", AllowedBackends: []keyring.BackendType{backend}, KeychainName: "login", KeychainAccessibleWhenUnlocked: true, WinCredPrefix: "bilimbi-native:"})
	if err != nil {
		return nil, errors.New("operating system credential store unavailable")
	}
	return nativeVault{ring}, nil
}

type profileStore struct {
	dir    string
	native func() (vault, error)
}

func newStore() (*profileStore, error) {
	root, err := os.UserConfigDir()
	if err != nil {
		return nil, errors.New("cannot locate user configuration directory")
	}
	return &profileStore{filepath.Join(root, "bilimbi"), openNative}, nil
}
func (s *profileStore) load() (profiles, error) {
	p := profiles{Items: map[string]profile{}}
	data, err := os.ReadFile(filepath.Join(s.dir, "profiles.json"))
	if os.IsNotExist(err) {
		return p, nil
	}
	if err != nil || json.Unmarshal(data, &p) != nil || p.Items == nil {
		return p, errors.New("cannot read profile store")
	}
	for _, item := range p.Items {
		d := item.Discovery
		origin, err := serverAddress(d.Server)
		if err != nil || origin != d.Server || d.ClientID != "bilimbi-native" || d.Version != "1" || !sameOrigin(origin, d.API) || !sameOrigin(origin, d.Token) || !sameOrigin(origin, d.Device) || (item.Backend != "native" && item.Backend != "file") {
			return p, errors.New("invalid stored profile; sign in again")
		}
	}
	return p, nil
}
func (s *profileStore) save(p profiles) error {
	return writeJSON(filepath.Join(s.dir, "profiles.json"), p)
}
func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return errors.New("cannot encode local data")
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return errors.New("cannot create local data directory")
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".bilimbi-*")
	if err != nil {
		return errors.New("cannot create local data file")
	}
	defer os.Remove(file.Name())
	if err = secureFile(file); err == nil {
		_, err = file.Write(data)
	}
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Rename(file.Name(), path)
	}
	if err != nil {
		return errors.New("cannot save local data")
	}
	return nil
}

// One exclusive lock covers read/rotate/persist. A stale lock is deliberately
// not reclaimed: deleting a live lock could replay a rotated refresh token.
func (s *profileStore) lock(ctx context.Context) (func(), error) {
	if err := os.MkdirAll(s.dir, 0700); err != nil {
		return nil, errors.New("cannot create profile directory")
	}
	lockCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	path := filepath.Join(s.dir, "store.lock")
	for {
		f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err == nil {
			f.Close()
			return func() { _ = os.Remove(path) }, nil
		}
		if !os.IsExist(err) {
			return nil, errors.New("cannot lock profile store")
		}
		if waitContext(lockCtx, 50*time.Millisecond) != nil {
			return nil, errors.New("profile store busy; if a client crashed, remove store.lock only after all Bilimbi commands have stopped")
		}
	}
}
func credentialKey(server string) string {
	sum := sha256.Sum256([]byte(server))
	return hex.EncodeToString(sum[:])
}
func (s *profileStore) credentialPath(server string) string {
	return filepath.Join(s.dir, "credentials", credentialKey(server)+".json")
}
func (s *profileStore) get(p profile) (credentials, error) {
	var data []byte
	var err error
	if p.Backend == "native" {
		var v vault
		v, err = s.native()
		if err == nil {
			data, err = v.Get(credentialKey(p.Discovery.Server))
		}
	} else {
		path := s.credentialPath(p.Discovery.Server)
		info, e := os.Lstat(path)
		if e != nil || !privateFile(path, info) {
			return credentials{}, errors.New("credential file missing or permissions unsafe")
		}
		data, err = os.ReadFile(path)
	}
	var c credentials
	if err != nil || json.Unmarshal(data, &c) != nil || c.Access == "" || c.Refresh == "" {
		return c, errors.New("credential unavailable; sign in again")
	}
	return c, nil
}
func (s *profileStore) put(server string, c credentials, backend string) (string, error) {
	data, _ := json.Marshal(c)
	if backend == "" || backend == "native" {
		v, err := s.native()
		if err == nil {
			err = v.Set(credentialKey(server), data)
		}
		if err == nil {
			return "native", nil
		}
		if backend == "native" {
			return "", errors.New("cannot persist rotated credential; sign in again")
		}
	}
	if err := writeJSON(s.credentialPath(server), c); err != nil {
		return "", err
	}
	return "file", nil
}
func (s *profileStore) delete(p profile) error {
	if p.Backend == "file" {
		err := os.Remove(s.credentialPath(p.Discovery.Server))
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	v, err := s.native()
	if err != nil {
		return err
	}
	err = v.Delete(credentialKey(p.Discovery.Server))
	if errors.Is(err, keyring.ErrKeyNotFound) {
		return nil
	}
	if err != nil {
		return errors.New("cannot remove operating system credential")
	}
	return nil
}
