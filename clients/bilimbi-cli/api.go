package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const deviceGrant = "urn:ietf:params:oauth:grant-type:device_code"
const maxJSON = 8 << 20

type discovery struct {
	Server   string `json:"server"`
	Name     string `json:"server_name"`
	API      string `json:"api_base"`
	Version  string `json:"api_version"`
	ClientID string `json:"client_id"`
	Device   string `json:"device_authorization_endpoint"`
	Token    string `json:"token_endpoint"`
}
type credentials struct {
	Access  string    `json:"access_token"`
	Refresh string    `json:"refresh_token"`
	Expires time.Time `json:"expires_at"`
}
type tokenReply struct {
	Access  string `json:"access_token"`
	Refresh string `json:"refresh_token"`
	Type    string `json:"token_type"`
	Expires int    `json:"expires_in"`
	Error   string `json:"error"`
}
type apiClient struct {
	http       *http.Client
	agent, run string
	secrets    []string
	wait       func(context.Context, time.Duration) error
}

func newClient(agent, run string) *apiClient {
	return &apiClient{http: &http.Client{Timeout: 30 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}, agent: agent, run: run, wait: waitContext}
}
func waitContext(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-timer.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
func serverAddress(address string) (string, error) {
	if !strings.Contains(address, "://") {
		address = "http://" + address
	}
	u, err := url.Parse(address)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Scheme != "http" && u.Scheme != "https") || (u.Path != "" && u.Path != "/") {
		return "", errors.New("server address must be an HTTP(S) origin, without credentials or a path")
	}
	return strings.ToLower(u.Scheme + "://" + u.Host), nil
}
func sameOrigin(server, endpoint string) bool {
	origin, err := url.Parse(server)
	if err != nil {
		return false
	}
	u, err := url.Parse(endpoint)
	return err == nil && u.Scheme == origin.Scheme && strings.EqualFold(u.Host, origin.Host) && u.User == nil && u.RawQuery == "" && u.Fragment == "" && u.Path != ""
}

// Never return transport errors, response bodies or OAuth error descriptions:
// each may echo credentials. Only bounded, allowlisted error codes cross this seam.
func (c *apiClient) request(ctx context.Context, method, endpoint string, body any, access string, result any) (int, error) {
	var input io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return 0, errors.New("invalid JSON request")
		}
		input = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, input)
	if err != nil {
		return 0, errors.New("invalid endpoint")
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if access != "" {
		req.Header.Set("Authorization", "Bearer "+access)
	}
	req.Header.Set("X-Bilimbi-Agent-Id", c.agent)
	req.Header.Set("X-Bilimbi-Run-Id", c.run)
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, errors.New("request failed; check the server and network")
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxJSON+1))
	if err != nil || len(data) > maxJSON {
		return resp.StatusCode, errors.New("response unreadable or too large")
	}
	if resp.StatusCode >= 300 && result == nil {
		return resp.StatusCode, fmt.Errorf("server returned HTTP %d", resp.StatusCode)
	}
	if result != nil && json.Unmarshal(data, result) != nil {
		return resp.StatusCode, errors.New("server returned invalid JSON")
	}
	return resp.StatusCode, nil
}
func (c *apiClient) discover(ctx context.Context, address string) (discovery, error) {
	server, err := serverAddress(address)
	if err != nil {
		return discovery{}, err
	}
	var d discovery
	status, err := c.request(ctx, "GET", server+"/.well-known/bilimbi", nil, "", &d)
	if err != nil {
		return d, err
	}
	if status != 200 {
		return d, fmt.Errorf("discovery returned HTTP %d", status)
	}
	var oauth struct {
		Issuer string   `json:"issuer"`
		Device string   `json:"device_authorization_endpoint"`
		Token  string   `json:"token_endpoint"`
		Grants []string `json:"grant_types_supported"`
	}
	status, err = c.request(ctx, "GET", server+"/.well-known/oauth-authorization-server", nil, "", &oauth)
	if err != nil {
		return d, err
	}
	if status != 200 {
		return d, fmt.Errorf("OAuth discovery returned HTTP %d", status)
	}
	issuer, err := serverAddress(oauth.Issuer)
	hasDevice, hasRefresh := false, false
	for _, grant := range oauth.Grants {
		hasDevice = hasDevice || grant == deviceGrant
		hasRefresh = hasRefresh || grant == "refresh_token"
	}
	if err != nil || issuer != server || d.Version != "1" || d.ClientID != "bilimbi-native" || !hasDevice || !hasRefresh || !sameOrigin(server, d.API) || !sameOrigin(server, oauth.Device) || !sameOrigin(server, oauth.Token) {
		return d, errors.New("incompatible discovery or endpoint outside the supplied server")
	}
	d.Server, d.Device, d.Token = server, oauth.Device, oauth.Token
	return d, nil
}
func (c *apiClient) login(ctx context.Context, d discovery, output io.Writer) (credentials, error) {
	var device struct {
		Device   string `json:"device_code"`
		User     string `json:"user_code"`
		URI      string `json:"verification_uri"`
		Expires  int    `json:"expires_in"`
		Interval int    `json:"interval"`
	}
	status, err := c.request(ctx, "POST", d.Device, map[string]string{"client_id": d.ClientID, "agent_id": c.agent}, "", &device)
	if err != nil {
		return credentials{}, err
	}
	if status != 200 || device.Device == "" || device.User == "" || device.Expires <= 0 || !sameOrigin(d.Server, device.URI) {
		return credentials{}, errors.New("device authorization failed")
	}
	c.secrets = append(c.secrets, device.Device)
	fmt.Fprint(output, c.redact(fmt.Sprintf("Open %s and enter code %s\n", device.URI, device.User)))
	interval := time.Duration(max(device.Interval, 5)) * time.Second
	pollCtx, cancel := context.WithTimeout(ctx, time.Duration(device.Expires)*time.Second)
	defer cancel()
	for {
		if c.wait(pollCtx, interval) != nil {
			return credentials{}, errors.New("device sign-in expired or cancelled")
		}
		var reply tokenReply
		status, err = c.request(pollCtx, "POST", d.Token, map[string]string{"client_id": d.ClientID, "device_code": device.Device, "grant_type": deviceGrant}, "", &reply)
		if err != nil {
			return credentials{}, err
		}
		switch reply.Error {
		case "authorization_pending":
			continue
		case "slow_down":
			interval += 5 * time.Second
			continue
		case "access_denied", "expired_token":
			return credentials{}, errors.New("device sign-in refused or expired")
		case "":
			if status == 200 {
				return c.acceptToken(reply)
			}
		}
		return credentials{}, errors.New("device sign-in failed")
	}
}
func (c *apiClient) acceptToken(reply tokenReply) (credentials, error) {
	c.secrets = append(c.secrets, reply.Access, reply.Refresh)
	if reply.Access == "" || reply.Refresh == "" || !strings.EqualFold(reply.Type, "Bearer") || reply.Expires <= 0 {
		return credentials{}, errors.New("invalid token response; sign in again")
	}
	return credentials{Access: reply.Access, Refresh: reply.Refresh, Expires: time.Now().Add(time.Duration(reply.Expires) * time.Second)}, nil
}
func (c *apiClient) refresh(ctx context.Context, d discovery, creds credentials) (credentials, error) {
	c.secrets = append(c.secrets, creds.Access, creds.Refresh)
	var reply tokenReply
	status, err := c.request(ctx, "POST", d.Token, map[string]string{"client_id": d.ClientID, "grant_type": "refresh_token", "refresh_token": creds.Refresh}, "", &reply)
	// A lost refresh response may already have rotated the credential. Never retry.
	if err != nil || status != 200 {
		return credentials{}, errors.New("refresh failed; sign in again (rotation was not retried)")
	}
	return c.acceptToken(reply)
}
func (c *apiClient) api(ctx context.Context, d discovery, creds credentials, method, path string, body any) (json.RawMessage, error) {
	c.secrets = append(c.secrets, creds.Access, creds.Refresh)
	var result json.RawMessage
	status, err := c.request(ctx, method, strings.TrimRight(d.API, "/")+path, body, creds.Access, &result)
	if err != nil {
		return nil, err
	}
	if status != 200 {
		return nil, fmt.Errorf("API returned HTTP %d", status)
	}
	var value any
	decoder := json.NewDecoder(bytes.NewReader(result))
	decoder.UseNumber()
	if decoder.Decode(&value) != nil {
		return nil, errors.New("server returned invalid JSON")
	}
	return json.Marshal(c.redactJSON(value))
}
func (c *apiClient) redactJSON(value any) any {
	switch v := value.(type) {
	case string:
		return c.redact(v)
	case []any:
		for i := range v {
			v[i] = c.redactJSON(v[i])
		}
		return v
	case map[string]any:
		clean := make(map[string]any, len(v))
		for key, item := range v {
			clean[c.redact(key)] = c.redactJSON(item)
		}
		return clean
	default:
		return value
	}
}
func (c *apiClient) redact(value string) string {
	for _, secret := range c.secrets {
		if secret != "" {
			value = strings.ReplaceAll(value, secret, "[REDACTED]")
			encoded, _ := json.Marshal(secret)
			value = strings.ReplaceAll(value, string(encoded[1:len(encoded)-1]), "[REDACTED]")
		}
	}
	return value
}
