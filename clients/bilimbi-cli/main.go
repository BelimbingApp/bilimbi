package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"time"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	store, err := newStore()
	if err == nil {
		err = run(ctx, os.Args[1:], os.Stdin, os.Stdout, os.Stderr, store)
	}
	if err != nil {
		_ = json.NewEncoder(os.Stderr).Encode(map[string]string{"error": err.Error()})
		os.Exit(1)
	}
}
func outputJSON(out io.Writer, value any) error { return json.NewEncoder(out).Encode(value) }
func readJSON(input io.Reader, path string, value any) error {
	if path != "-" {
		f, err := os.Open(path)
		if err != nil {
			return errors.New("cannot open JSON input file")
		}
		defer f.Close()
		input = f
	}
	if input == nil {
		return errors.New("JSON input is unavailable")
	}
	data, err := io.ReadAll(io.LimitReader(input, maxJSON+1))
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err != nil || len(data) > maxJSON || decoder.Decode(value) != nil || decoder.Decode(new(any)) != io.EOF {
		return errors.New("input must be one JSON document, at most 8 MiB")
	}
	return nil
}

// Parse global flags separately so both 'bilimbi --agent-id … search …' and
// 'bilimbi search … --agent-id …' work without shell wrappers.
func globals(args []string) ([]string, string, string, error) {
	agent, run := os.Getenv("BILIMBI_AGENT_ID"), os.Getenv("BILIMBI_RUN_ID")
	rest := []string{}
	for i := 0; i < len(args); i++ {
		name, value, has := strings.Cut(args[i], "=")
		if name != "--agent-id" && name != "--run-id" {
			rest = append(rest, args[i])
			continue
		}
		if !has {
			i++
			if i == len(args) {
				return nil, "", "", errors.New("missing header flag value")
			}
			value = args[i]
		}
		if name == "--agent-id" {
			agent = value
		} else {
			run = value
		}
	}
	for _, value := range []string{agent, run} {
		if len(value) > 200 || strings.ContainsAny(value, "\r\n") {
			return nil, "", "", errors.New("invalid agent or run header")
		}
	}
	return rest, agent, run, nil
}
func run(ctx context.Context, args []string, input io.Reader, out, errout io.Writer, store *profileStore) error {
	args, agent, runID, err := globals(args)
	if err != nil {
		return err
	}
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" {
		fmt.Fprintln(out, "bilimbi login <address> [--name <profile>] | logout [name] | profiles | use <name>\nbilimbi search <words> | describe <key> | guide <key> | call <key> [--input <file|->]\nbilimbi review --input <file|-> [--session <file>] [--timeout 30m]\nbilimbi report --input <file|-> [--session <file>] [--timeout 30m]\nHeaders: --agent-id harness/model-ver-effort --run-id <run>, or BILIMBI_AGENT_ID/BILIMBI_RUN_ID.\nJSON goes to stdout; browser addresses and device codes go to stderr.")
		return nil
	}
	command, tail := args[0], args[1:]
	if command == "review" || command == "report" {
		return localCommand(ctx, command, tail, input, out, errout)
	}
	client := newClient(agent, runID)
	if command == "login" {
		if agent == "" {
			return errors.New("login requires --agent-id or BILIMBI_AGENT_ID (harness/model-ver-effort)")
		}
		if len(tail) == 0 {
			return errors.New("login requires a server address")
		}
		flags := flag.NewFlagSet("login", flag.ContinueOnError)
		flags.SetOutput(io.Discard)
		name := flags.String("name", "", "profile name")
		if flags.Parse(tail[1:]) != nil || flags.NArg() != 0 {
			return errors.New("usage: login <address> [--name <profile>]")
		}
		d, err := client.discover(ctx, tail[0])
		if err != nil {
			return err
		}
		creds, err := client.login(ctx, d, errout)
		if err != nil {
			return err
		}
		unlock, err := store.lock(ctx)
		if err != nil {
			return err
		}
		defer unlock()
		ps, err := store.load()
		if err != nil {
			return err
		}
		if *name == "" {
			*name = d.Server
		}
		if strings.TrimSpace(*name) == "" || len(*name) > 200 {
			return errors.New("invalid profile name")
		}
		if previous, ok := ps.Items[*name]; ok && previous.Discovery.Server != d.Server {
			return errors.New("profile name already belongs to a different server")
		}
		backend, err := store.put(d.Server, creds, "")
		if err != nil {
			return err
		}
		// Credentials are keyed by server. All aliases must agree on its backend.
		for key, p := range ps.Items {
			if p.Discovery.Server == d.Server {
				p.Backend = backend
				p.Discovery = d
				p.NeedsLogin = false
				ps.Items[key] = p
			}
		}
		ps.Items[*name] = profile{Discovery: d, Backend: backend}
		ps.Active = *name
		if err = store.save(ps); err != nil {
			return err
		}
		return outputJSON(out, map[string]string{"profile": *name, "server": d.Server, "credential_backend": backend})
	}
	unlock, err := store.lock(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	ps, err := store.load()
	if err != nil {
		return err
	}
	switch command {
	case "profiles":
		if len(tail) != 0 {
			return errors.New("profiles takes no arguments")
		}
		return outputJSON(out, ps)
	case "use":
		if len(tail) != 1 {
			return errors.New("use requires a profile name")
		}
		if _, ok := ps.Items[tail[0]]; !ok {
			return errors.New("unknown profile")
		}
		ps.Active = tail[0]
		if err = store.save(ps); err != nil {
			return err
		}
		return outputJSON(out, map[string]string{"active": ps.Active})
	case "logout":
		if len(tail) > 1 {
			return errors.New("logout accepts one profile name")
		}
		name := ps.Active
		if len(tail) == 1 {
			name = tail[0]
		}
		p, ok := ps.Items[name]
		if !ok {
			return errors.New("unknown profile")
		}
		if err = store.delete(p); err != nil {
			return err
		}
		for key, item := range ps.Items {
			if item.Discovery.Server == p.Discovery.Server {
				delete(ps.Items, key)
				if ps.Active == key {
					ps.Active = ""
				}
			}
		}
		if err = store.save(ps); err != nil {
			return err
		}
		return outputJSON(out, map[string]string{"logged_out": name})
	}
	if command != "search" && command != "describe" && command != "guide" && command != "call" {
		return errors.New("unknown command; use bilimbi help")
	}
	if agent == "" || runID == "" {
		return errors.New("API commands require agent and run IDs via flags or environment")
	}
	p, ok := ps.Items[ps.Active]
	if !ok {
		return errors.New("no active profile; use login or use")
	}
	if p.NeedsLogin {
		return errors.New("previous refresh did not finish safely; sign in again")
	}
	creds, err := store.get(p)
	if err != nil {
		return err
	}
	if time.Until(creds.Expires) < time.Minute {
		// Persist uncertainty before sending a one-use refresh token. If the
		// process crashes or loses the response, no later command may replay it.
		for name, item := range ps.Items {
			if item.Discovery.Server == p.Discovery.Server {
				item.NeedsLogin = true
				ps.Items[name] = item
			}
		}
		if err = store.save(ps); err != nil {
			return err
		}
		creds, err = client.refresh(ctx, p.Discovery, creds)
		if err != nil {
			return err
		}
		if _, err = store.put(p.Discovery.Server, creds, p.Backend); err != nil {
			return err
		}
		for name, item := range ps.Items {
			if item.Discovery.Server == p.Discovery.Server {
				item.NeedsLogin = false
				ps.Items[name] = item
			}
		}
		if err = store.save(ps); err != nil {
			return err
		}
	}
	var path, method string
	var body any
	method = "GET"
	switch command {
	case "search":
		if len(tail) == 0 {
			return errors.New("search requires words")
		}
		path = "/search?q=" + url.QueryEscape(strings.Join(tail, " "))
	case "describe", "guide":
		if len(tail) != 1 {
			return errors.New("describe and guide require one key")
		}
		resource := "operations"
		if command == "guide" {
			resource = "guides"
		}
		path = "/" + resource + "/" + url.PathEscape(tail[0])
	case "call":
		if len(tail) == 0 {
			return errors.New("call requires an operation key")
		}
		flags := flag.NewFlagSet("call", flag.ContinueOnError)
		flags.SetOutput(io.Discard)
		file := flags.String("input", "-", "JSON input")
		if flags.Parse(tail[1:]) != nil || flags.NArg() != 0 {
			return errors.New("usage: call <key> [--input <file|->]")
		}
		var values map[string]any
		if err = readJSON(input, *file, &values); err != nil {
			return err
		}
		if values == nil {
			return errors.New("call input must be a JSON object")
		}
		path = "/operations/" + url.PathEscape(tail[0])
		description, err := client.api(ctx, p.Discovery, creds, "GET", path, nil)
		if err != nil {
			return err
		}
		var op struct {
			Kind string `json:"kind"`
		}
		if json.Unmarshal(description, &op) != nil || op.Kind != "read" {
			return errors.New("this client only calls read operations")
		}
		path += "/call"
		method = "POST"
		body = map[string]any{"input": values}
	}
	result, err := client.api(ctx, p.Discovery, creds, method, path, body)
	if err != nil {
		return err
	}
	return outputJSON(out, result)
}
