package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

func TestPlanAndCommitPreserveInputsAndServerBinding(t *testing.T) {
	code := strings.Repeat("p", 43)
	var planned json.RawMessage
	committed := 0
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer access" || r.Header.Get("X-Bilimbi-Run-Id") != "task" {
			t.Error("missing identity headers")
		}
		var body struct {
			Operations json.RawMessage `json:"operations"`
			Code       string          `json:"plan_code"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		switch r.URL.Path {
		case "/api/v1/plans":
			planned = append(json.RawMessage(nil), body.Operations...)
			_ = outputJSON(w, map[string]any{"valid": true, "plan_code": code, "results": []any{}})
		case "/api/v1/plans/commit":
			committed++
			if body.Code != code || !bytes.Equal(planned, body.Operations) {
				t.Errorf("commit changed operations: %s vs %s", planned, body.Operations)
			}
			_ = outputJSON(w, map[string]any{"results": []any{map[string]any{"key": "core.employee.create", "record": map[string]any{"id": 1}, "url": "http://" + r.Host + "/employees/1"}}})
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	})
	store, _ := testStore(t)
	d := exampleDiscovery(server.URL)
	_, err := store.put(d.Server, credentials{Access: "access", Refresh: "refresh", Expires: time.Now().Add(time.Hour)}, "")
	if err != nil {
		t.Fatal(err)
	}
	if err = store.save(profiles{Active: "test", Items: map[string]profile{"test": {Discovery: d, Backend: "native"}}}); err != nil {
		t.Fatal(err)
	}
	var out, stderr bytes.Buffer
	args := []string{"plan", "--agent-id", "codex/test-high", "--run-id", "task"}
	input := `{"operations":[{"key":"core.employee.create","input":{"employer_company_id":9223372036854775807,"full_name":"Ada","employee_number":"CONTACT-1"}}]}`
	if err = run(context.Background(), args, strings.NewReader(input), &out, &stderr, store); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(planPath(store, code))
	if err != nil || !privateFile(planPath(store, code), info) {
		t.Fatal("plan inputs must be private", err)
	}
	args = []string{"commit", "--plan", code, "--agent-id", "codex/test-high", "--run-id", "task"}
	out.Reset()
	if err = run(context.Background(), args, nil, &out, &stderr, store); err != nil {
		t.Fatal(err)
	}
	if committed != 1 || !strings.Contains(string(planned), "9223372036854775807") {
		t.Fatal("lost exact integer")
	}
	saved := savedPlan{Server: "http://other.test", Code: code}
	if err = writeJSON(planPath(store, code), saved); err != nil {
		t.Fatal(err)
	}
	if err = run(context.Background(), args, nil, &out, &stderr, store); err == nil {
		t.Fatal("cross-server plan accepted")
	}
	if committed != 1 {
		t.Fatal("cross-server plan sent")
	}
	for _, bad := range []string{"../secret", "", strings.Repeat("x", 44)} {
		args[2] = bad
		if run(context.Background(), args, nil, &out, &stderr, store) == nil {
			t.Fatal("invalid plan code accepted")
		}
	}
}

func TestAPIPlanReviewUsesValidatedReadOnlyChangesAndCommitReportLinks(t *testing.T) {
	raw := json.RawMessage(`{"valid":true,"expires_at":"2026-10-11T14:00:00Z","results":[{"key":"core.company.create","valid":true,"preview":{"summary":"Create company","changes":[{"field":"name","from":null,"to":"Example <script>"}]}}]}`)
	doc, err := localDocument(raw, "review")
	if err != nil {
		t.Fatal(err)
	}
	if !doc.ReadOnly || len(doc.Rows) != 1 || doc.Rows[0]["to"] != "Example <script>" {
		t.Fatal("review lost server evidence")
	}
	page, err := startLocal(doc, "review")
	if err != nil {
		t.Fatal(err)
	}
	defer page.shutdown()
	response, err := http.Get(page.url)
	if err != nil {
		t.Fatal(err)
	}
	var html bytes.Buffer
	_, _ = html.ReadFrom(response.Body)
	response.Body.Close()
	if strings.Contains(html.String(), `name="cell-`) || strings.Contains(html.String(), "Example <script>") {
		t.Fatal("review can edit evidence or inject HTML")
	}
	approval := localRequest(t, page, "/submit", "http://"+page.host, "application/x-www-form-urlencoded", strings.NewReader(url.Values{"decision": {"approve"}, "cell-0-3": {"tampered"}}.Encode()))
	if approval.StatusCode != http.StatusSeeOther {
		t.Fatalf("review could not approve: %d", approval.StatusCode)
	}
	select {
	case submission := <-page.submitted:
		if !submission.Approved || submission.Document.Rows[0]["to"] != "Example <script>" {
			t.Fatal("submission changed API evidence")
		}
	default:
		t.Fatal("approval submission missing")
	}
	report, err := localDocument(json.RawMessage(`{"results":[{"key":"core.company.create","record":{"id":12,"name":"Example"},"url":"http://server/companies/12"}]}`), "report")
	if err != nil || len(report.Links) != 1 || report.Links[0].URL != "http://server/companies/12" {
		t.Fatal("missing server verification links", err)
	}
	if validateDocument(report) != nil {
		t.Fatal("invalid report")
	}
}

func TestCommitRefusalPreservesStructuredEvidenceAndNeverReportsSuccess(t *testing.T) {
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(422)
		_ = outputJSON(w, map[string]any{"error": "plan_rejected", "results": []any{map[string]any{"error": map[string]any{"code": "invalid_input", "fields": map[string]any{"email": []string{"private-token has invalid format"}}}}}})
	})
	c := newClient("a", "r")
	result, err := c.api(context.Background(), discovery{API: server.URL}, credentials{Access: "private-token", Refresh: "refresh"}, "POST", "/plans/commit", map[string]any{})
	if err == nil || !strings.Contains(err.Error(), "plan_rejected") || strings.Contains(string(result), "private-token") {
		t.Fatal("unsafe or missing refusal evidence", err, string(result))
	}
	doc, err := localDocument(result, "report")
	if err != nil || doc.Title != "Changes were refused" || len(doc.Links) != 0 || len(doc.Rows) != 1 {
		t.Fatal("refusal presented as a success", err)
	}
}
