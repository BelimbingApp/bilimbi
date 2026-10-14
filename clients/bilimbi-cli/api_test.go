package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func fakeServer(t *testing.T, handler func(http.ResponseWriter, *http.Request)) *httptest.Server {
	t.Helper()
	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/.well-known/bilimbi":
			_ = outputJSON(w, discovery{Name: "Test", API: server.URL + "/api/v1", Version: "1", ClientID: "bilimbi-native"})
		case "/.well-known/oauth-authorization-server":
			_ = outputJSON(w, map[string]any{"issuer": server.URL, "device_authorization_endpoint": server.URL + "/oauth/device_authorization", "token_endpoint": server.URL + "/oauth/token", "grant_types_supported": []string{deviceGrant, "refresh_token"}})
		default:
			handler(w, r)
		}
	}))
	t.Cleanup(server.Close)
	return server
}
func TestDiscoveryAndDeviceFlow(t *testing.T) {
	polls := 0
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		var body map[string]string
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Error(err)
		}
		if body["client_id"] != "bilimbi-native" {
			t.Error("public client ID missing")
		}
		switch r.URL.Path {
		case "/oauth/device_authorization":
			if body["agent_id"] != "codex/test-high" {
				t.Error("agent missing")
			}
			_ = outputJSON(w, map[string]any{"device_code": "private-device", "user_code": "ABCD-EFGH", "verification_uri": "http://" + r.Host + "/oauth/device", "expires_in": 600, "interval": 5})
		case "/oauth/token":
			if body["device_code"] != "private-device" || body["grant_type"] != deviceGrant {
				t.Error("wrong grant")
			}
			polls++
			switch polls {
			case 1:
				w.WriteHeader(400)
				_ = outputJSON(w, map[string]string{"error": "authorization_pending"})
			case 2:
				w.WriteHeader(400)
				_ = outputJSON(w, map[string]string{"error": "slow_down"})
			default:
				_ = outputJSON(w, tokenReply{Access: "private-access", Refresh: "private-refresh", Type: "Bearer", Expires: 3600})
			}
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	})
	client := newClient("codex/test-high", "run-1")
	var intervals []time.Duration
	client.wait = func(_ context.Context, d time.Duration) error { intervals = append(intervals, d); return nil }
	d, err := client.discover(context.Background(), server.URL)
	if err != nil {
		t.Fatal(err)
	}
	var shown bytes.Buffer
	creds, err := client.login(context.Background(), d, &shown)
	if err != nil {
		t.Fatal(err)
	}
	if creds.Access != "private-access" || creds.Refresh != "private-refresh" || time.Until(creds.Expires) < 59*time.Minute {
		t.Fatal("incorrect credentials")
	}
	if polls != 3 || len(intervals) != 3 || intervals[0] != 5*time.Second || intervals[2] != 10*time.Second {
		t.Fatalf("incorrect polling %v", intervals)
	}
	if !strings.Contains(shown.String(), "ABCD-EFGH") || strings.Contains(shown.String(), "private-") {
		t.Fatalf("unsafe sign-in output %s", shown.String())
	}
}
func TestDiscoverCommandNeedsNoIdentityOrCredentials(t *testing.T) {
	t.Setenv("BILIMBI_AGENT_ID", "")
	t.Setenv("BILIMBI_RUN_ID", "")
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("discovery attempted authentication or API call: %s", r.URL.Path)
	})
	store, vault := testStore(t)
	var out, errout bytes.Buffer
	if err := run(context.Background(), []string{"discover", server.URL}, nil, &out, &errout, store); err != nil {
		t.Fatal(err)
	}
	var result discovery
	if err := json.Unmarshal(out.Bytes(), &result); err != nil || result.Server != server.URL || result.API != server.URL+"/api/v1" {
		t.Fatalf("unusable discovery output: %s", out.String())
	}
	profiles, err := store.load()
	if err != nil || len(profiles.Items) != 0 || len(vault) != 0 || errout.Len() != 0 {
		t.Fatal("discovery changed credentials or profiles")
	}
	for _, args := range [][]string{{"discover"}, {"discover", server.URL, "extra"}} {
		if err := run(context.Background(), args, nil, &out, &errout, store); err == nil {
			t.Fatal("invalid discover arguments accepted")
		}
	}
}

func TestDiscoveryExplainsCompatibilityAndOriginFailures(t *testing.T) {
	for _, mismatch := range []string{"origin", "version", "client", "grants"} {
		t.Run(mismatch, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				origin := "http://" + r.Host
				d := discovery{API: origin + "/api/v1", Version: "1", ClientID: "bilimbi-native"}
				issuer, grants := origin, []string{deviceGrant, "refresh_token"}
				switch mismatch {
				case "origin":
					issuer = "http://canonical.example"
				case "version":
					d.Version = "2"
				case "client":
					d.ClientID = "another-client"
				case "grants":
					grants = []string{deviceGrant}
				}
				if r.URL.Path == "/.well-known/bilimbi" {
					_ = outputJSON(w, d)
				} else {
					_ = outputJSON(w, map[string]any{"issuer": issuer, "device_authorization_endpoint": origin + "/device", "token_endpoint": origin + "/token", "grant_types_supported": grants})
				}
			}))
			defer server.Close()
			_, err := newClient("", "").discover(context.Background(), server.URL)
			if err == nil {
				t.Fatal("incompatible server accepted")
			}
			want := "incompatible discovery"
			if mismatch == "origin" {
				want = "canonical address"
			}
			if !strings.Contains(err.Error(), want) {
				t.Fatalf("missing recovery guidance: %v", err)
			}
		})
	}
}

func TestDiscoveryRefusesCrossOriginAndRedirect(t *testing.T) {
	stolen := 0
	attacker := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { stolen++; w.WriteHeader(200) }))
	defer attacker.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/.well-known/bilimbi" {
			_ = outputJSON(w, discovery{API: attacker.URL + "/api/v1", Version: "1", ClientID: "bilimbi-native"})
			return
		}
		_ = outputJSON(w, map[string]any{"issuer": "http://" + r.Host, "device_authorization_endpoint": attacker.URL + "/device", "token_endpoint": attacker.URL + "/token", "grant_types_supported": []string{deviceGrant, "refresh_token"}})
	}))
	defer server.Close()
	if _, err := newClient("a", "r").discover(context.Background(), server.URL); err == nil {
		t.Fatal("cross-origin discovery accepted")
	}
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, attacker.URL, 302) }))
	defer redirect.Close()
	if _, err := newClient("a", "r").discover(context.Background(), redirect.URL); err == nil {
		t.Fatal("redirect accepted")
	}
	if stolen != 0 {
		t.Fatal("contacted untrusted server")
	}
	for _, address := range []string{"http://user:password@example.test", "file:///etc/passwd", "http://example.test/path", "http://example.test?token=secret"} {
		if _, err := serverAddress(address); err == nil {
			t.Errorf("accepted %s", address)
		}
	}
}
func TestDeviceRefusalCancellationAndExpiry(t *testing.T) {
	for _, code := range []string{"access_denied", "expired_token"} {
		t.Run(code, func(t *testing.T) {
			server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/oauth/device_authorization" {
					_ = outputJSON(w, map[string]any{"device_code": "secret", "user_code": "CODE", "verification_uri": "http://" + r.Host + "/oauth/device", "expires_in": 60})
				} else {
					w.WriteHeader(400)
					_ = outputJSON(w, map[string]string{"error": code, "error_description": "secret"})
				}
			})
			c := newClient("a", "r")
			c.wait = func(context.Context, time.Duration) error { return nil }
			d, err := c.discover(context.Background(), server.URL)
			if err != nil {
				t.Fatal(err)
			}
			if _, err = c.login(context.Background(), d, &bytes.Buffer{}); err == nil || strings.Contains(err.Error(), "secret") {
				t.Fatal("unsafe refusal")
			}
		})
	}
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = outputJSON(w, map[string]any{"device_code": "secret", "user_code": "CODE", "verification_uri": "http://" + r.Host + "/oauth/device", "expires_in": 60})
	})
	c := newClient("a", "r")
	c.wait = func(context.Context, time.Duration) error { return context.DeadlineExceeded }
	d, err := c.discover(context.Background(), server.URL)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = c.login(context.Background(), d, &bytes.Buffer{}); err == nil {
		t.Fatal("expired login accepted")
	}
}

type failingTransport struct{}

func (failingTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, errors.New("private-access private-refresh private-device")
}
func TestCredentialRedactionAndRefreshNotRetried(t *testing.T) {
	c := newClient("a", "r")
	creds := credentials{Access: "private-access", Refresh: "private-refresh"}
	c.http.Transport = failingTransport{}
	if _, err := c.refresh(context.Background(), discovery{Token: "http://example.test/token"}, creds); err == nil || strings.Contains(err.Error(), "private-") {
		t.Fatal("transport error leaked credentials")
	}
	rotations := 0
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		rotations++
		w.WriteHeader(401)
		fmtBody := `{"error":"private-access private-refresh"}`
		_, _ = w.Write([]byte(fmtBody))
	})
	if _, err := newClient("a", "r").refresh(context.Background(), discovery{Token: server.URL + "/token"}, creds); err == nil || strings.Contains(err.Error(), "private-") {
		t.Fatal("HTTP error leaked credentials")
	}
	if rotations != 1 {
		t.Fatal("rotation retried")
	}
	c = newClient("codex/test-high", "run-1")
	echo := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer private-access" || r.Header.Get("X-Bilimbi-Agent-Id") != "codex/test-high" || r.Header.Get("X-Bilimbi-Run-Id") != "run-1" {
			t.Error("missing API headers")
		}
		_ = outputJSON(w, map[string]string{"result": "private-access private-refresh"})
	})
	data, err := c.api(context.Background(), discovery{API: echo.URL + "/api/v1"}, creds, "GET", "/search", nil)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "private-") || !json.Valid(data) {
		t.Fatalf("unsafe output %s", data)
	}
}

func TestAPIJSONPreservesLargeNumbersAndEscapedRedaction(t *testing.T) {
	token := "private\"token"
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = outputJSON(w, map[string]any{"id": json.Number("9223372036854775807"), "nested": []any{map[string]string{"echo": token}}})
	})
	c := newClient("a", "r")
	data, err := c.api(context.Background(), discovery{API: server.URL}, credentials{Access: token, Refresh: "refresh"}, "GET", "/read", nil)
	if err != nil {
		t.Fatal(err)
	}
	var result map[string]any
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if decoder.Decode(&result) != nil || result["id"] != json.Number("9223372036854775807") || strings.Contains(string(data), "private") {
		t.Fatalf("JSON contract corrupted: %s", data)
	}
	var input map[string]any
	if err := readJSON(strings.NewReader(`{"id":9223372036854775807}`), "-", &input); err != nil || input["id"] != json.Number("9223372036854775807") {
		t.Fatal("input rounded")
	}
}
