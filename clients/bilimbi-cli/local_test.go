package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func testDocument() document {
	return document{Title: "Company review", Columns: []column{{"name", "Name"}, {"count", "Count"}, {"enabled", "Enabled"}}, Rows: []map[string]any{{"name": "Example", "count": float64(2), "enabled": true, "id": "retain-this"}}}
}
func localRequest(t *testing.T, p *localPage, path, origin, content string, body io.Reader) *http.Response {
	t.Helper()
	req, err := http.NewRequest("POST", p.url+path, body)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Origin", origin)
	req.Header.Set("Content-Type", content)
	c := http.Client{Timeout: time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := c.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}
func TestReviewEditCommentApproveReportAndClose(t *testing.T) {
	p, err := startLocal(testDocument(), "review")
	if err != nil {
		t.Fatal(err)
	}
	defer p.shutdown()
	if !strings.HasPrefix(p.url, "http://127.0.0.1:") || len(p.path) != 65 {
		t.Fatal("unsafe local address")
	}
	resp, err := http.Get(p.url)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 || resp.Header.Get("Cache-Control") != "no-store" {
		t.Fatal("review not served")
	}
	form := url.Values{"cell-0-0": {"Edited company"}, "cell-0-1": {"3"}, "cell-0-2": {"false"}, "comment": {"Check this address"}, "decision": {"approve"}}
	resp = localRequest(t, p, "/submit", "http://"+p.host, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if resp.StatusCode != 303 {
		t.Fatal("submission refused", resp.StatusCode)
	}
	select {
	case result := <-p.submitted:
		if !result.Approved || result.Comment != "Check this address" || result.Document.Rows[0]["name"] != "Edited company" || result.Document.Rows[0]["count"] != json.Number("3") || result.Document.Rows[0]["enabled"] != false || result.Document.Rows[0]["id"] != "retain-this" {
			t.Fatal("edit not preserved", result)
		}
	case <-time.After(time.Second):
		t.Fatal("submission never delivered")
	}
	resp = localRequest(t, p, "/submit", "http://"+p.host, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if resp.StatusCode != 409 {
		t.Fatal("replayed submission accepted")
	}
	report := testDocument()
	report.Title = "Results"
	report.Links = []link{{"Company", "http://example.test/companies/12"}}
	data, _ := json.Marshal(report)
	resp = localRequest(t, p, "/report", "http://"+p.host, "application/json", bytes.NewReader(data))
	if resp.StatusCode != 200 {
		t.Fatal("report refused")
	}
	resp, err = http.Get(p.url)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(body), "http://example.test/companies/12") {
		t.Fatal("report link not shown")
	}
	resp = localRequest(t, p, "/submit", "http://"+p.host, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if resp.StatusCode != 409 {
		t.Fatal("submission accepted after report")
	}
	resp = localRequest(t, p, "/close", "http://"+p.host, "application/x-www-form-urlencoded", nil)
	if resp.StatusCode != 200 {
		t.Fatal("close refused")
	}
	select {
	case <-p.done:
	case <-time.After(time.Second):
		t.Fatal("close not signaled")
	}
	p.shutdown()
	if _, err = http.Get(p.url); err == nil {
		t.Fatal("listener remains open")
	}
}
func TestReviewGuardsAndEscapesContent(t *testing.T) {
	d := testDocument()
	d.Title = "<script>alert(1)</script>"
	d.Rows[0]["name"] = "</textarea><script>bad()</script>"
	p, err := startLocal(d, "review")
	if err != nil {
		t.Fatal(err)
	}
	defer p.shutdown()
	resp, err := http.Get(p.url)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if strings.Contains(string(body), "<script>") || !strings.Contains(string(body), "&lt;script&gt;") {
		t.Fatal("HTML not escaped")
	}
	if !strings.Contains(resp.Header.Get("Content-Security-Policy"), "frame-ancestors 'none'") {
		t.Fatal("missing frame policy")
	}
	resp, err = http.Get("http://" + p.host + "/wrong")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatal("unguarded path")
	}
	req, _ := http.NewRequest("GET", p.url, nil)
	req.Host = "attacker.test"
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatal("host accepted")
	}
	resp = localRequest(t, p, "/submit", "http://attacker.test", "application/x-www-form-urlencoded", strings.NewReader("decision=approve"))
	if resp.StatusCode != 403 {
		t.Fatal("foreign origin accepted")
	}
	resp = localRequest(t, p, "/submit", "http://"+p.host, "application/x-www-form-urlencoded", strings.NewReader("decision=approve"))
	if resp.StatusCode != 400 {
		t.Fatal("missing cells accepted")
	}
	resp = localRequest(t, p, "/close", "http://"+p.host, "application/x-www-form-urlencoded", nil)
	if resp.StatusCode != 409 {
		t.Fatal("unsubmitted review closed")
	}
	bad := testDocument()
	bad.Links = []link{{"Bad", "javascript:alert(1)"}}
	if _, err = startLocal(bad, "report"); err == nil {
		t.Fatal("unsafe report link")
	}
}

type notifyWriter struct{ lines chan string }

func (w notifyWriter) Write(data []byte) (int, error) { w.lines <- string(data); return len(data), nil }
func TestReviewCommandSamePageReportAndSessionCleanup(t *testing.T) {
	d := testDocument()
	data, _ := json.Marshal(d)
	session := filepath.Join(t.TempDir(), "session.json")
	stdout, stderr := notifyWriter{make(chan string, 4)}, notifyWriter{make(chan string, 4)}
	finished := make(chan error, 1)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	go func() {
		finished <- localCommand(ctx, "review", []string{"--session", session}, bytes.NewReader(data), stdout, stderr, nil)
	}()
	var address string
	select {
	case line := <-stderr.lines:
		address = strings.TrimSpace(strings.TrimPrefix(line, "Open "))
	case <-ctx.Done():
		t.Fatal("page not started")
	}
	var descriptor localSession
	if err := readJSON(nil, session, &descriptor); err != nil || descriptor.URL != address {
		t.Fatal("session not stored", err)
	}
	u, _ := url.Parse(address)
	p := &localPage{url: address, host: u.Host}
	form := url.Values{"cell-0-0": {"Example"}, "cell-0-1": {"2"}, "cell-0-2": {"true"}, "decision": {"revise"}}
	resp := localRequest(t, p, "/submit", "http://"+p.host, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if resp.StatusCode != 303 {
		t.Fatal("review refused")
	}
	select {
	case line := <-stdout.lines:
		var result submission
		if json.Unmarshal([]byte(line), &result) != nil || result.Approved {
			t.Fatal("revision not reported")
		}
	case <-ctx.Done():
		t.Fatal("submission not printed")
	}
	var reportOut bytes.Buffer
	if err := localCommand(ctx, "report", []string{"--session", session}, bytes.NewReader(data), &reportOut, io.Discard, nil); err != nil {
		t.Fatal(err)
	}
	resp = localRequest(t, p, "/close", "http://"+p.host, "application/x-www-form-urlencoded", nil)
	if resp.StatusCode != 200 {
		t.Fatal("report close refused")
	}
	select {
	case err := <-finished:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal("review did not exit")
	}
	if _, err := os.Stat(session); !os.IsNotExist(err) {
		t.Fatal("session capability left behind")
	}
}
func TestReviewTimeoutCleansSession(t *testing.T) {
	data, _ := json.Marshal(testDocument())
	session := filepath.Join(t.TempDir(), "session.json")
	ctx, cancel := context.WithCancel(context.Background())
	finished := make(chan error, 1)
	stderr := notifyWriter{make(chan string, 1)}
	go func() {
		finished <- localCommand(ctx, "review", []string{"--session", session}, bytes.NewReader(data), io.Discard, stderr, nil)
	}()
	var address string
	select {
	case line := <-stderr.lines:
		address = strings.TrimSpace(strings.TrimPrefix(line, "Open "))
	case <-time.After(time.Second):
		t.Fatal("page not started")
	}
	cancel()
	select {
	case err := <-finished:
		if err == nil {
			t.Fatal("cancel not reported")
		}
	case <-time.After(time.Second):
		t.Fatal("cancel ignored")
	}
	if _, err := os.Stat(session); !os.IsNotExist(err) {
		t.Fatal("session not cleaned")
	}
	if _, err := http.Get(address); err == nil {
		t.Fatal("listener not closed")
	}
}
func TestReviewSubmitNormalizesLineEndings(t *testing.T) {
	d := testDocument()
	d.Rows[0]["name"] = "\nLine1\nLine2"
	p, err := startLocal(d, "review")
	if err != nil {
		t.Fatal(err)
	}
	defer p.shutdown()
	form := url.Values{"cell-0-0": {"\r\nLine1\r\nLine2"}, "cell-0-1": {"2"}, "cell-0-2": {"true"}, "decision": {"revise"}}
	resp := localRequest(t, p, "/submit", "http://"+p.host, "application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if resp.StatusCode != 303 {
		t.Fatal("submission refused", resp.StatusCode)
	}
	select {
	case result := <-p.submitted:
		if result.Document.Rows[0]["name"] != "\nLine1\nLine2" {
			t.Fatalf("line endings not normalized: %q", result.Document.Rows[0]["name"])
		}
	case <-time.After(time.Second):
		t.Fatal("submission never delivered")
	}
}
