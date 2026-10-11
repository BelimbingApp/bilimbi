package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

type memoryVault map[string][]byte

func (v memoryVault) Get(key string) ([]byte, error) {
	data, ok := v[key]
	if !ok {
		return nil, errors.New("not found")
	}
	return data, nil
}
func (v memoryVault) Set(key string, data []byte) error {
	v[key] = append([]byte(nil), data...)
	return nil
}
func (v memoryVault) Delete(key string) error { delete(v, key); return nil }
func testStore(t *testing.T) (*profileStore, memoryVault) {
	t.Helper()
	v := memoryVault{}
	return &profileStore{dir: t.TempDir(), native: func() (vault, error) { return v, nil }}, v
}
func exampleDiscovery(server string) discovery {
	return discovery{Server: server, Name: "Example", API: server + "/api/v1", Version: "1", ClientID: "bilimbi-native", Device: server + "/oauth/device", Token: server + "/oauth/token"}
}
func TestProfilesAndServerKeyedCredentials(t *testing.T) {
	s, v := testStore(t)
	a, b := exampleDiscovery("http://one.test"), exampleDiscovery("http://two.test")
	for _, d := range []discovery{a, b} {
		if _, err := s.put(d.Server, credentials{Access: d.Name + "-access", Refresh: "refresh", Expires: time.Now().Add(time.Hour)}, ""); err != nil {
			t.Fatal(err)
		}
	}
	ps := profiles{Active: "one", Items: map[string]profile{"one": {Discovery: a, Backend: "native"}, "two": {Discovery: b, Backend: "native"}, "alias": {Discovery: a, Backend: "native"}}}
	if err := s.save(ps); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := run(context.Background(), []string{"use", "two"}, nil, &out, &out, s); err != nil {
		t.Fatal(err)
	}
	loaded, err := s.load()
	if err != nil || loaded.Active != "two" {
		t.Fatal("profile switch not stored")
	}
	out.Reset()
	if err = run(context.Background(), []string{"profiles"}, nil, &out, &out, s); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out.String(), "Example-access") || strings.Contains(out.String(), "refresh") {
		t.Fatal("credentials leaked in profile listing")
	}
	if err = run(context.Background(), []string{"logout", "one"}, nil, &out, &out, s); err != nil {
		t.Fatal(err)
	}
	loaded, err = s.load()
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded.Items) != 1 || loaded.Active != "two" || len(v) != 1 {
		t.Fatal("logout did not remove server aliases and credentials")
	}
	if _, err = s.get(loaded.Items["two"]); err != nil {
		t.Fatal("other server credential removed")
	}
}
func TestPrivateFileFallback(t *testing.T) {
	s, _ := testStore(t)
	s.native = func() (vault, error) { return nil, errors.New("unavailable secret service") }
	d := exampleDiscovery("http://example.test")
	c := credentials{Access: "access", Refresh: "refresh", Expires: time.Now().Add(time.Hour)}
	backend, err := s.put(d.Server, c, "")
	if err != nil || backend != "file" {
		t.Fatal("fallback failed", err)
	}
	info, err := os.Stat(s.credentialPath(d.Server))
	if err != nil || !privateFile(s.credentialPath(d.Server), info) {
		t.Fatal("unsafe fallback permissions")
	}
	got, err := s.get(profile{Discovery: d, Backend: backend})
	if err != nil || got.Access != c.Access {
		t.Fatal("fallback not round tripped", err)
	}
	if runtime.GOOS != "windows" {
		if err = os.Chmod(s.credentialPath(d.Server), 0644); err != nil {
			t.Fatal(err)
		}
		if _, err = s.get(profile{Discovery: d, Backend: backend}); err == nil {
			t.Fatal("world-readable credential accepted")
		}
	}
	if err = s.delete(profile{Discovery: d, Backend: backend}); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(s.credentialPath(d.Server)); !os.IsNotExist(err) {
		t.Fatal("fallback not deleted")
	}
}
func TestProfileLockCancellationAndCorruption(t *testing.T) {
	s, _ := testStore(t)
	unlock, err := s.lock(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err = s.lock(ctx); err == nil {
		t.Fatal("concurrent lock accepted")
	}
	unlock()
	unlock, err = s.lock(context.Background())
	if err != nil {
		t.Fatal("lock not released")
	}
	unlock()
	if err = os.WriteFile(filepath.Join(s.dir, "profiles.json"), []byte(`{"active":"one","profiles":{"one":{"discovery":{"server":"http://one.test","api_base":"http://evil.test/api"},"credential_backend":"native"}}}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = s.load(); err == nil {
		t.Fatal("tampered profile accepted")
	}
}
func TestCommandReadsAndRefusesWrites(t *testing.T) {
	s, _ := testStore(t)
	calls, refreshes := 0, 0
	kind := "read"
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/oauth/token":
			refreshes++
			_ = outputJSON(w, tokenReply{Access: "rotated-access", Refresh: "rotated-refresh", Type: "Bearer", Expires: 3600})
		case "/api/v1/operations/core.test":
			_ = outputJSON(w, map[string]string{"kind": kind})
		case "/api/v1/operations/core.test/call":
			calls++
			if r.Header.Get("Authorization") != "Bearer rotated-access" {
				t.Error("unrotated token")
			}
			var body map[string]any
			if json.NewDecoder(r.Body).Decode(&body) != nil || body["input"] == nil {
				t.Error("invalid call body")
			}
			_ = outputJSON(w, map[string]any{"result": map[string]string{"name": "Example"}, "meta": map[string]string{"content_notice": "data"}})
		case "/api/v1/search":
			if r.URL.Query().Get("q") != "company records" {
				t.Error("wrong query")
			}
			_ = outputJSON(w, map[string]any{"result": []any{}})
		case "/api/v1/guides/core.test":
			_ = outputJSON(w, map[string]string{"body": "Guide"})
		default:
			t.Errorf("unexpected request %s", r.URL.Path)
			w.WriteHeader(404)
		}
	})
	d := exampleDiscovery(server.URL)
	if _, err := s.put(d.Server, credentials{Access: "old-access", Refresh: "old-refresh", Expires: time.Now().Add(-time.Minute)}, ""); err != nil {
		t.Fatal(err)
	}
	if err := s.save(profiles{Active: "test", Items: map[string]profile{"test": {Discovery: d, Backend: "native"}}}); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	for _, args := range [][]string{{"call", "core.test"}, {"describe", "core.test"}, {"search", "company", "records"}, {"guide", "core.test"}} {
		args = append(args, "--agent-id", "codex/test-high", "--run-id", "run-1")
		if err := run(context.Background(), args, strings.NewReader(`{"name":"Example"}`), &out, &bytes.Buffer{}, s); err != nil {
			t.Fatal(err)
		}
	}
	if calls != 1 || refreshes != 1 {
		t.Fatalf("calls %d refreshes %d", calls, refreshes)
	}
	p, err := s.load()
	if err != nil {
		t.Fatal(err)
	}
	stored, err := s.get(p.Items["test"])
	if err != nil || stored.Refresh != "rotated-refresh" {
		t.Fatal("rotation not persisted")
	}
	kind = "write"
	if err = run(context.Background(), []string{"call", "core.test", "--agent-id", "a", "--run-id", "r"}, strings.NewReader(`{}`), &out, &bytes.Buffer{}, s); err == nil || calls != 1 {
		t.Fatal("write called")
	}
	if strings.Contains(out.String(), "rotated-") {
		t.Fatal("token leaked")
	}
}

func TestFailedRefreshRequiresLoginOnLaterCommands(t *testing.T) {
	s, _ := testStore(t)
	rotations := 0
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		rotations++
		w.WriteHeader(400)
		_ = outputJSON(w, map[string]string{"error": "invalid_grant"})
	})
	d := exampleDiscovery(server.URL)
	if _, err := s.put(d.Server, credentials{Access: "old-access", Refresh: "old-refresh", Expires: time.Now().Add(-time.Minute)}, ""); err != nil {
		t.Fatal(err)
	}
	if err := s.save(profiles{Active: "test", Items: map[string]profile{"test": {Discovery: d, Backend: "native"}, "alias": {Discovery: d, Backend: "native"}}}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if err := run(context.Background(), []string{"search", "company", "--agent-id", "a", "--run-id", "r"}, nil, &bytes.Buffer{}, &bytes.Buffer{}, s); err == nil {
			t.Fatal("failed rotation accepted")
		}
	}
	if rotations != 1 {
		t.Fatal("later command replayed uncertain refresh")
	}
	p, err := s.load()
	if err != nil || !p.Items["test"].NeedsLogin || !p.Items["alias"].NeedsLogin {
		t.Fatal("rotation uncertainty not retained across aliases")
	}
}
