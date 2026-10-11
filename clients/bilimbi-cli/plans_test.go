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
			_ = outputJSON(w, map[string]any{"valid": true, "plan_code": code, "expires_at": time.Now().Add(10 * time.Minute).UTC().Format(time.RFC3339), "operations": planned, "results": []any{}})
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
	if err = run(context.Background(), args, nil, &out, &stderr, store); err == nil || committed != 0 {
		t.Fatal("commit without an approved review was sent", err)
	}
	if err = recordReview(store, json.RawMessage(reviewedPlanJSON(t, code, planned)), true); err != nil {
		t.Fatal(err)
	}
	if err = run(context.Background(), args, nil, &out, &stderr, store); err != nil {
		t.Fatal(err)
	}
	if committed != 1 || !strings.Contains(string(planned), "9223372036854775807") {
		t.Fatal("lost exact integer")
	}
	for _, leftover := range []string{planPath(store, code), approvalPath(store, code)} {
		if _, statErr := os.Stat(leftover); statErr == nil {
			t.Fatal("committed plan left on disk")
		}
	}
	if err = run(context.Background(), args, nil, &out, &stderr, store); err == nil || committed != 1 {
		t.Fatal("approval was not consumed")
	}
	saved := savedPlan{Server: "http://other.test", Code: code}
	if err = writeJSON(planPath(store, code), saved); err != nil {
		t.Fatal(err)
	}
	if err = writeJSON(approvalPath(store, code), map[string]string{"plan_code": code}); err != nil {
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
	var plan savedPlan
	if err := json.Unmarshal(raw, &plan); err != nil {
		t.Fatal(err)
	}
	doc := reviewDocument(plan)
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

func reviewedPlanJSON(t *testing.T, code string, operations json.RawMessage) string {
	t.Helper()
	return `{"valid":true,"plan_code":"` + code + `","operations":` + string(operations) + `,"results":[{"key":"core.employee.create","valid":true,"preview":{"changes":[]}}]}`
}

func TestApprovalIsBoundToTheReviewedPlanAndExpiredPlansArePruned(t *testing.T) {
	store, _ := testStore(t)
	codeA, codeB := strings.Repeat("a", 43), strings.Repeat("b", 43)
	operationsA := []plannedOperation{{Key: "core.company.create", Input: map[string]any{"name": "A"}}}
	operationsB := []plannedOperation{{Key: "core.company.create", Input: map[string]any{"name": "B"}}}
	soon := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	for code, operations := range map[string][]plannedOperation{codeA: operationsA, codeB: operationsB} {
		if err := writeJSON(planPath(store, code), savedPlan{Server: "s", Code: code, Expires: soon, Operations: operations}); err != nil {
			t.Fatal(err)
		}
	}
	review := func(code string, operations []plannedOperation) json.RawMessage {
		raw, _ := json.Marshal(map[string]any{"valid": true, "plan_code": code, "operations": operations, "results": []any{}})
		return raw
	}
	if recordReview(store, review(strings.Repeat("c", 43), operationsA), true) == nil {
		t.Fatal("review of an unknown plan accepted")
	}
	if err := recordReview(store, review(codeA, operationsA), true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(approvalPath(store, codeA)); err != nil {
		t.Fatal("approval marker missing")
	}
	if _, err := os.Stat(approvalPath(store, codeB)); err == nil {
		t.Fatal("review of plan A unlocked plan B")
	}
	custom, _ := json.Marshal(map[string]any{"plan_code": codeB, "columns": []any{}, "rows": []any{}, "title": "x"})
	if err := recordReview(store, custom, true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(approvalPath(store, codeB)); err == nil {
		t.Fatal("custom document unlocked a plan")
	}
	past := time.Now().Add(-time.Minute).UTC().Format(time.RFC3339)
	if err := writeJSON(planPath(store, codeB), savedPlan{Server: "s", Code: codeB, Expires: past, Operations: operationsB}); err != nil {
		t.Fatal(err)
	}
	if err := writeJSON(approvalPath(store, codeB), map[string]string{"plan_code": codeB}); err != nil {
		t.Fatal(err)
	}
	prunePlans(store)
	for _, gone := range []string{planPath(store, codeB), approvalPath(store, codeB)} {
		if _, err := os.Stat(gone); err == nil {
			t.Fatal("expired plan kept")
		}
	}
	if _, err := os.Stat(planPath(store, codeA)); err != nil {
		t.Fatal("live plan pruned")
	}
}

func submitReview(t *testing.T, store *profileStore, plan []byte, decision string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	stdout, stderr := notifyWriter{make(chan string, 4)}, notifyWriter{make(chan string, 4)}
	finished := make(chan error, 1)
	go func() {
		finished <- localCommand(ctx, "review", nil, bytes.NewReader(plan), stdout, stderr, store)
	}()
	var address string
	select {
	case line := <-stderr.lines:
		address = strings.TrimSpace(strings.TrimPrefix(line, "Open "))
	case <-ctx.Done():
		t.Fatal("page not started")
	}
	u, _ := url.Parse(address)
	page := &localPage{url: address, host: u.Host}
	resp := localRequest(t, page, "/submit", "http://"+page.host, "application/x-www-form-urlencoded", strings.NewReader(url.Values{"decision": {decision}}.Encode()))
	if resp.StatusCode != http.StatusSeeOther {
		t.Fatalf("review refused: %d", resp.StatusCode)
	}
	if err := <-finished; err != nil {
		t.Fatal(err)
	}
}

func TestRequestingChangesWithdrawsEarlierApproval(t *testing.T) {
	code := strings.Repeat("w", 43)
	requests := 0
	server := fakeServer(t, func(w http.ResponseWriter, r *http.Request) {
		requests++
		_ = outputJSON(w, map[string]any{"results": []any{}})
	})
	store, _ := testStore(t)
	d := exampleDiscovery(server.URL)
	if _, err := store.put(d.Server, credentials{Access: "access", Refresh: "refresh", Expires: time.Now().Add(time.Hour)}, ""); err != nil {
		t.Fatal(err)
	}
	if err := store.save(profiles{Active: "test", Items: map[string]profile{"test": {Discovery: d, Backend: "native"}}}); err != nil {
		t.Fatal(err)
	}
	operations := []plannedOperation{{Key: "core.company.create", Input: map[string]any{"name": "A"}}}
	expires := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	if err := writeJSON(planPath(store, code), savedPlan{Server: d.Server, Code: code, Expires: expires, Operations: operations}); err != nil {
		t.Fatal(err)
	}
	plan, _ := json.Marshal(map[string]any{"valid": true, "plan_code": code, "expires_at": expires, "operations": operations, "results": []any{map[string]any{"key": "core.company.create", "valid": true, "preview": map[string]any{"changes": []any{map[string]any{"field": "name", "from": nil, "to": "A"}}}}}})
	submitReview(t, store, plan, "approve")
	if _, err := os.Stat(approvalPath(store, code)); err != nil {
		t.Fatal("approval marker missing", err)
	}
	submitReview(t, store, plan, "revise")
	if _, err := os.Stat(approvalPath(store, code)); err == nil {
		t.Fatal("requesting changes kept the approval")
	}
	var out, stderr bytes.Buffer
	args := []string{"commit", "--plan", code, "--agent-id", "codex/test-high", "--run-id", "task"}
	if err := run(context.Background(), args, nil, &out, &stderr, store); err == nil || requests != 0 {
		t.Fatal("withdrawn plan was committed", err)
	}
}

func TestReviewShowsSavedResultsNotResultsCarriedByTheInput(t *testing.T) {
	store, _ := testStore(t)
	code := strings.Repeat("t", 43)
	saved := savedPlan{Server: "s", Code: code, Expires: time.Now().Add(time.Hour).UTC().Format(time.RFC3339)}
	if err := json.Unmarshal([]byte(`{"results":[{"key":"core.company.create","valid":true,"preview":{"changes":[{"field":"name","from":null,"to":"Real change"}]}}]}`), &saved); err != nil {
		t.Fatal(err)
	}
	if err := writeJSON(planPath(store, code), saved); err != nil {
		t.Fatal(err)
	}
	tampered, _ := json.Marshal(map[string]any{"valid": true, "plan_code": code, "results": []any{map[string]any{"key": "core.company.create", "valid": true, "preview": map[string]any{"changes": []any{map[string]any{"field": "name", "from": nil, "to": "Benign"}}}}}})
	reviewed, err := savedForReview(store, tampered)
	if err != nil || reviewed == nil {
		t.Fatal("saved plan not found", err)
	}
	doc := reviewDocument(*reviewed)
	if len(doc.Rows) != 1 || doc.Rows[0]["to"] != "Real change" {
		t.Fatalf("review displayed agent-supplied results: %v", doc.Rows)
	}
	if _, err = savedForReview(store, json.RawMessage(`{"valid":true,"results":[{"key":"x","valid":true}]}`)); err == nil {
		t.Fatal("review of an unsaved plan accepted")
	}
}
