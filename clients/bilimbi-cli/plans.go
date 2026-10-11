package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

type plannedOperation struct {
	Key   string         `json:"key"`
	Input map[string]any `json:"input"`
}
type planRequest struct {
	Operations []plannedOperation `json:"operations"`
}
type savedPlan struct {
	Server     string             `json:"server"`
	Code       string             `json:"plan_code"`
	Expires    string             `json:"expires_at"`
	Operations []plannedOperation `json:"operations"`
}
type planResponse struct {
	Valid      bool               `json:"valid"`
	Code       string             `json:"plan_code"`
	Expires    string             `json:"expires_at"`
	Operations []plannedOperation `json:"operations"`
	Results    []struct {
		Key     string         `json:"key"`
		Valid   bool           `json:"valid"`
		Error   map[string]any `json:"error"`
		Preview struct {
			Summary string `json:"summary"`
			Changes []struct {
				Field string `json:"field"`
				From  any    `json:"from"`
				To    any    `json:"to"`
			} `json:"changes"`
		} `json:"preview"`
	} `json:"results"`
}

var codePattern = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)

func validPlanCode(code string) bool { return codePattern.MatchString(code) }
func planPath(store *profileStore, code string) string {
	return filepath.Join(store.dir, "plans", code+".json")
}
func approvalPath(store *profileStore, code string) string {
	return filepath.Join(store.dir, "plans", code+".approved")
}

// Plan files hold the exact reviewed inputs. Once a plan has expired or been
// committed its file and approval marker are removed; the next command that
// touches the plans directory removes any that expired without being committed.
func prunePlans(store *profileStore) {
	entries, _ := os.ReadDir(filepath.Join(store.dir, "plans"))
	for _, entry := range entries {
		code, isPlan := strings.CutSuffix(entry.Name(), ".json")
		if !isPlan || !validPlanCode(code) {
			continue
		}
		var saved savedPlan
		_ = readJSON(nil, planPath(store, code), &saved)
		if expires, err := time.Parse(time.RFC3339, saved.Expires); err != nil || !expires.After(time.Now()) {
			discardPlan(store, code)
		}
	}
}
func discardPlan(store *profileStore, code string) {
	_ = os.Remove(planPath(store, code))
	_ = os.Remove(approvalPath(store, code))
}

// The person's go is enforced here, not by Bilimbi. A submitted approval of an
// API plan response unlocks only the saved plan with that code, and only when
// the reviewed operations are the saved ones.
func approvePlan(store *profileStore, raw json.RawMessage) error {
	var values map[string]json.RawMessage
	if json.Unmarshal(raw, &values) != nil {
		return errors.New("invalid local document")
	}
	if _, custom := values["columns"]; custom {
		return nil
	}
	var plan planResponse
	if err := readJSON(bytes.NewReader(raw), "-", &plan); err != nil || !plan.Valid {
		return nil
	}
	prunePlans(store)
	var saved savedPlan
	if !validPlanCode(plan.Code) || readJSON(nil, planPath(store, plan.Code), &saved) != nil || saved.Code != plan.Code {
		return errors.New("reviewed plan is unavailable locally; create a new plan")
	}
	reviewed, _ := json.Marshal(plan.Operations)
	planned, _ := json.Marshal(saved.Operations)
	if !bytes.Equal(reviewed, planned) {
		return errors.New("reviewed operations differ from the saved plan; create a new plan")
	}
	return writeJSON(approvalPath(store, plan.Code), map[string]string{"plan_code": plan.Code})
}

// The API's changes are review evidence. Editing them would not edit the saved
// operations. Ask for changes in the comment, then generate and review a new plan.
func localDocument(raw json.RawMessage, mode string) (document, error) {
	var values map[string]json.RawMessage
	if json.Unmarshal(raw, &values) != nil {
		return document{}, errors.New("invalid local document")
	}
	if _, ok := values["columns"]; ok {
		var doc document
		if err := readJSON(bytes.NewReader(raw), "-", &doc); err != nil {
			return doc, err
		}
		return doc, nil
	}
	if mode == "review" {
		var plan planResponse
		if err := readJSON(bytes.NewReader(raw), "-", &plan); err != nil || len(plan.Results) == 0 {
			return document{}, errors.New("review needs a document or API plan results")
		}
		doc := document{ReadOnly: true, Title: "Review changes", Summary: "Validated changes from Bilimbi. Nothing has been written. Request changes in the comment; changed inputs require a new plan.", Columns: []column{{"operation", "Operation"}, {"field", "Field"}, {"from", "Before"}, {"to", "After"}}}
		if plan.Expires != "" {
			doc.Summary += " Review expires at " + plan.Expires + "."
		}
		if !plan.Valid {
			doc.Summary = "Bilimbi refused this plan. Resolve the errors and create a new plan."
		}
		for _, result := range plan.Results {
			if !result.Valid {
				doc.Rows = append(doc.Rows, map[string]any{"operation": result.Key, "field": "Refused", "from": nil, "to": result.Error})
				continue
			}
			for _, change := range result.Preview.Changes {
				doc.Rows = append(doc.Rows, map[string]any{"operation": result.Key, "field": change.Field, "from": change.From, "to": change.To})
			}
		}
		return doc, nil
	}
	if _, refused := values["error"]; refused {
		var failure map[string]any
		if err := readJSON(bytes.NewReader(raw), "-", &failure); err != nil {
			return document{}, err
		}
		return document{Title: "Changes were refused", Summary: "Bilimbi did not commit this plan. Resolve the refusal and review a new plan before retrying.", Columns: []column{{"outcome", "Outcome"}}, Rows: []map[string]any{{"outcome": failure}}}, nil
	}
	var report struct {
		Results []struct {
			Key    string         `json:"key"`
			Record map[string]any `json:"record"`
			URL    string         `json:"url"`
		} `json:"results"`
	}
	if err := readJSON(bytes.NewReader(raw), "-", &report); err != nil || len(report.Results) == 0 {
		return document{}, errors.New("report needs a document or committed API results")
	}
	doc := document{Title: "Changes made", Summary: "Bilimbi committed these records. Open the links to verify them.", Columns: []column{{"operation", "Operation"}, {"record", "Record"}}}
	for _, result := range report.Results {
		doc.Rows = append(doc.Rows, map[string]any{"operation": result.Key, "record": result.Record})
		doc.Links = append(doc.Links, link{result.Key, result.URL})
	}
	return doc, nil
}
