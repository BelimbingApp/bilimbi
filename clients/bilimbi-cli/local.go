package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"html/template"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

type column struct {
	Key   string `json:"key"`
	Label string `json:"label"`
}
type link struct {
	Label string `json:"label"`
	URL   string `json:"url"`
}

// This document is local presentation data, not a server plan or proof of go.
// Job 4 can carry a validated API plan in rows without changing the lifecycle.
type document struct {
	Title   string           `json:"title"`
	Summary string           `json:"summary,omitempty"`
	Columns []column         `json:"columns"`
	Rows    []map[string]any `json:"rows"`
	Links   []link           `json:"links,omitempty"`
}
type submission struct {
	Approved bool     `json:"approved"`
	Comment  string   `json:"comment"`
	Document document `json:"document"`
}
type localSession struct {
	URL string `json:"url"`
}
type localPage struct {
	mu              sync.Mutex
	doc             document
	mode            string
	received        bool
	url, path, host string
	server          *http.Server
	submitted       chan submission
	done            chan struct{}
	closeOnce       sync.Once
}

func validateDocument(d document) error {
	if d.Title == "" || len(d.Columns) == 0 || len(d.Columns) > 100 || len(d.Rows) > 10000 {
		return errors.New("local document needs a title, 1–100 columns, and at most 10000 rows")
	}
	keys := map[string]bool{}
	for _, c := range d.Columns {
		if c.Key == "" || c.Label == "" || keys[c.Key] {
			return errors.New("columns need unique keys and labels")
		}
		keys[c.Key] = true
	}
	for _, row := range d.Rows {
		if row == nil {
			return errors.New("rows must be JSON objects")
		}
	}
	for _, l := range d.Links {
		u, err := url.Parse(l.URL)
		if err != nil || u.Host == "" || u.User != nil || (u.Scheme != "http" && u.Scheme != "https") {
			return errors.New("report links must be HTTP(S) URLs without credentials")
		}
	}
	return nil
}
func startLocal(d document, mode string) (*localPage, error) {
	if err := validateDocument(d); err != nil {
		return nil, err
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return nil, errors.New("cannot listen on loopback")
	}
	secret := make([]byte, 32)
	if _, err = rand.Read(secret); err != nil {
		listener.Close()
		return nil, errors.New("cannot create review address")
	}
	path := "/" + hex.EncodeToString(secret)
	p := &localPage{doc: d, mode: mode, path: path, host: listener.Addr().String(), submitted: make(chan submission, 1), done: make(chan struct{})}
	p.url = "http://" + p.host + path
	p.server = &http.Server{Handler: p, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	go func() { _ = p.server.Serve(listener) }()
	return p, nil
}
func (p *localPage) stop() { p.closeOnce.Do(func() { close(p.done) }) }
func (p *localPage) shutdown() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_ = p.server.Shutdown(ctx)
}
func (p *localPage) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	// no-referrer makes browsers send Origin: null on ordinary form POSTs.
	// same-origin preserves our origin check without leaking the private path
	// to external pages (verification links also explicitly use noreferrer).
	w.Header().Set("Referrer-Policy", "same-origin")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
	if r.Host != p.host || (r.URL.Path != p.path && r.URL.Path != p.path+"/submit" && r.URL.Path != p.path+"/report" && r.URL.Path != p.path+"/close") {
		http.NotFound(w, r)
		return
	}
	if r.Method == "GET" && r.URL.Path == p.path {
		p.render(w)
		return
	}
	if r.Method != "POST" {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if r.Header.Get("Origin") != "http://"+p.host {
		http.Error(w, "Origin refused", 403)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxJSON)
	switch r.URL.Path {
	case p.path + "/submit":
		p.submit(w, r)
	case p.path + "/report":
		var d document
		decoder := json.NewDecoder(r.Body)
		decoder.UseNumber()
		if decoder.Decode(&d) != nil || decoder.Decode(new(any)) != io.EOF || validateDocument(d) != nil {
			http.Error(w, "Invalid report", 400)
			return
		}
		p.mu.Lock()
		if p.mode != "review" || !p.received {
			p.mu.Unlock()
			http.Error(w, "No submitted review", 409)
			return
		}
		p.doc = d
		p.mode = "report"
		p.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		_ = outputJSON(w, map[string]bool{"shown": true})
	case p.path + "/close":
		p.mu.Lock()
		ready := p.mode == "report"
		p.mu.Unlock()
		if !ready {
			http.Error(w, "Review still open", 409)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, "<!doctype html><title>Bilimbi</title><p>Report closed. You can close this tab.</p>")
		p.stop()
	default:
		http.NotFound(w, r)
	}
}
func (p *localPage) submit(w http.ResponseWriter, r *http.Request) {
	if r.ParseForm() != nil {
		http.Error(w, "Invalid form", 400)
		return
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.mode != "review" || p.received {
		http.Error(w, "Review already submitted", 409)
		return
	}
	decision := r.PostForm.Get("decision")
	if decision != "approve" && decision != "revise" {
		http.Error(w, "Choose approve or request changes", 400)
		return
	}
	d := p.doc
	d.Rows = make([]map[string]any, len(p.doc.Rows))
	for i, row := range p.doc.Rows {
		updated := map[string]any{}
		for k, v := range row {
			updated[k] = v
		}
		for j, col := range d.Columns {
			values, exists := r.PostForm[fmt.Sprintf("cell-%d-%d", i, j)]
			if !exists || len(values) != 1 {
				http.Error(w, "Missing field", 400)
				return
			}
			raw := values[0]
			var value any
			switch row[col.Key].(type) {
			case string:
				value = strings.ReplaceAll(raw, "\r\n", "\n")
			default:
				if readJSON(strings.NewReader(raw), "-", &value) != nil {
					http.Error(w, "Invalid field value; return and correct it", 400)
					return
				}
			}
			updated[col.Key] = value
		}
		d.Rows[i] = updated
	}
	p.received = true
	p.doc = d
	p.submitted <- submission{Approved: decision == "approve", Comment: r.PostForm.Get("comment"), Document: d}
	http.Redirect(w, r, p.path, http.StatusSeeOther)
}

type cellView struct{ Name, Label, Value, Kind string }
type pageView struct {
	Document   document
	Rows       [][]cellView
	Path, Mode string
	Received   bool
}

func (p *localPage) render(w http.ResponseWriter) {
	p.mu.Lock()
	defer p.mu.Unlock()
	view := pageView{Document: p.doc, Path: p.path, Mode: p.mode, Received: p.received}
	for i, row := range p.doc.Rows {
		cells := []cellView{}
		for j, c := range p.doc.Columns {
			raw, _ := json.Marshal(row[c.Key])
			value := string(raw)
			kind := "json"
			switch v := row[c.Key].(type) {
			case string:
				value = v
				kind = "text"
			case float64, json.Number:
				kind = "number"
			case bool:
				kind = "boolean"
			}
			cells = append(cells, cellView{fmt.Sprintf("cell-%d-%d", i, j), fmt.Sprintf("Row %d, %s", i+1, c.Label), value, kind})
		}
		view.Rows = append(view.Rows, cells)
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_ = localTemplate.Execute(w, view)
}

var localTemplate = template.Must(template.New("local").Parse(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{{.Document.Title}} · Bilimbi</title>
{{if and .Received (eq .Mode "review")}}<meta http-equiv="refresh" content="2">{{end}}
<style>body{font:14px system-ui,sans-serif;color:#292524;background:#fafaf9;margin:0;padding:24px}main{max-width:1100px;margin:auto}h1{font-size:22px;font-weight:600;color:#365314}p{line-height:1.5}table{border-collapse:collapse;width:100%;background:white}th,td{text-align:left;border:1px solid #d6d3d1;padding:8px;vertical-align:top}th{background:#f5f5f4;font-weight:600}input,textarea,select,button{font:inherit;border:1px solid #a8a29e;border-radius:4px;padding:7px;box-sizing:border-box}input,textarea{width:100%;min-width:100px}textarea{resize:vertical}button{cursor:pointer;background:white;margin:12px 8px 0 0}button.primary{background:#365314;color:white;border-color:#365314}a{color:#365314}label{display:block;margin:16px 0 5px}:focus-visible{outline:2px solid #65a30d;outline-offset:2px}.table{overflow:auto}.status{padding:12px;border:1px solid #a8a29e;background:white}.value{white-space:pre-wrap;overflow-wrap:anywhere}.badge{font-size:12px;color:#57534e}ul{padding-left:20px}@media(prefers-color-scheme:dark){body{background:#1c1917;color:#e7e5e4}h1,a{color:#bef264}table,.status,button,input,textarea,select{background:#292524;color:#e7e5e4}th{background:#44403c}}</style></head><body><main>
<p class="badge">Bilimbi · {{if eq .Mode "report"}}Results{{else}}Read-only review{{end}}</p><h1>{{.Document.Title}}</h1>{{if .Document.Summary}}<p>{{.Document.Summary}}</p>{{end}}
{{if and (eq .Mode "review") .Received}}<p class="status" role="status">Review submitted. Waiting for the agent's report.</p>{{end}}
<form method="post" action="{{.Path}}/submit"><div class="table"><table><thead><tr>{{range .Document.Columns}}<th scope="col">{{.Label}}</th>{{end}}</tr></thead><tbody>
{{range .Rows}}<tr>{{range .}}<td>{{if and (eq $.Mode "review") (not $.Received)}}
{{if eq .Kind "boolean"}}<select name="{{.Name}}" aria-label="{{.Label}}"><option value="true" {{if eq .Value "true"}}selected{{end}}>Yes</option><option value="false" {{if eq .Value "false"}}selected{{end}}>No</option></select>
{{else if eq .Kind "number"}}<input type="number" step="any" name="{{.Name}}" value="{{.Value}}" aria-label="{{.Label}}" required>
{{else}}<textarea name="{{.Name}}" aria-label="{{.Label}}" rows="2">
{{.Value}}</textarea>{{if eq .Kind "json"}}<small>JSON value</small>{{end}}{{end}}
{{else}}<div class="value">{{.Value}}</div>{{end}}</td>{{end}}</tr>{{else}}<tr><td colspan="{{len .Document.Columns}}">No records.</td></tr>{{end}}</tbody></table></div>
{{if and (eq .Mode "review") (not .Received)}}<label for="comment">Comments or questions</label><textarea id="comment" name="comment" rows="3"></textarea><button class="primary" name="decision" value="approve">Approve review</button><button name="decision" value="revise">Request changes</button>{{end}}</form>
{{if .Document.Links}}<h2>Verify in Bilimbi</h2><ul>{{range .Document.Links}}<li><a href="{{.URL}}" target="_blank" rel="noopener noreferrer">{{.Label}}</a></li>{{end}}</ul>{{end}}
{{if eq .Mode "report"}}<form method="post" action="{{.Path}}/close"><button class="primary">Close report</button></form>{{end}}
</main></body></html>`))

func localCommand(ctx context.Context, command string, args []string, input io.Reader, out, errout io.Writer) error {
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	file := flags.String("input", "-", "JSON document")
	sessionFile := flags.String("session", "", "local session descriptor")
	timeout := flags.Duration("timeout", 30*time.Minute, "page lifetime")
	if flags.Parse(args) != nil || flags.NArg() != 0 || *timeout <= 0 {
		return errors.New("usage: review|report --input <file|-> [--session <file>] [--timeout 30m]")
	}
	var d document
	if err := readJSON(input, *file, &d); err != nil {
		return err
	}
	if err := validateDocument(d); err != nil {
		return err
	}
	if command == "report" && *sessionFile != "" {
		var session localSession
		if err := readJSON(nil, *sessionFile, &session); err != nil {
			return err
		}
		u, err := url.Parse(session.URL)
		if err != nil || u.Scheme != "http" || u.Hostname() != "127.0.0.1" || u.Port() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || len(strings.TrimPrefix(u.Path, "/")) != 64 {
			return errors.New("invalid local session")
		}
		encoded, _ := json.Marshal(d)
		req, err := http.NewRequestWithContext(ctx, "POST", session.URL+"/report", strings.NewReader(string(encoded)))
		if err != nil {
			return errors.New("invalid local session")
		}
		req.Header.Set("Origin", "http://"+u.Host)
		req.Header.Set("Content-Type", "application/json")
		client := &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
		resp, err := client.Do(req)
		if err != nil {
			return errors.New("local review session unavailable")
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			return fmt.Errorf("local report refused (HTTP %d)", resp.StatusCode)
		}
		return outputJSON(out, map[string]bool{"shown": true})
	}
	p, err := startLocal(d, command)
	if err != nil {
		return err
	}
	defer p.shutdown()
	if *sessionFile != "" {
		if err = writeJSON(*sessionFile, localSession{p.url}); err != nil {
			return err
		}
		defer os.Remove(*sessionFile)
	}
	fmt.Fprintf(errout, "Open %s\n", p.url)
	pageCtx, cancel := context.WithTimeout(ctx, *timeout)
	defer cancel()
	if command == "review" {
		select {
		case result := <-p.submitted:
			if err = outputJSON(out, result); err != nil {
				return err
			}
		case <-pageCtx.Done():
			return errors.New("local review expired or cancelled")
		}
		if *sessionFile == "" {
			return nil
		}
	}
	select {
	case <-p.done:
		if command == "report" {
			return outputJSON(out, map[string]bool{"closed": true})
		}
		return nil
	case <-pageCtx.Done():
		return errors.New("local page expired or cancelled")
	}
}
