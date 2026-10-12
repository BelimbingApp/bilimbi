// Package creates a local Codex marketplace containing one platform's native
// executable and the same skill. It is build tooling, not a user-side runtime.
package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"debug/buildinfo"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"
)

func main() {
	root := flag.String("root", "../..", "repository root")
	binary := flag.String("binary", "", "compiled binary")
	target := flag.String("target", "", "OS-architecture")
	output := flag.String("output", "", "archive path")
	flag.Parse()
	if *binary == "" || *output == "" {
		fmt.Fprintln(os.Stderr, "binary and output required")
		os.Exit(1)
	}
	if err := pack(*root, *binary, *target, *output); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func pack(root, binary, target, output string) error {
	name := "bilimbi"
	switch target {
	case "windows-amd64":
		name += ".exe"
	case "darwin-arm64", "darwin-amd64", "linux-amd64":
	default:
		return fmt.Errorf("unsupported target")
	}
	file, err := os.Create(output)
	if err != nil {
		return err
	}
	z := zip.NewWriter(file)
	sources := map[string]string{
		"plugins/bilimbi/.codex-plugin/plugin.json": filepath.Join(root, "plugins/bilimbi/.codex-plugin/plugin.json"),
		"plugins/bilimbi/skills/bilimbi/SKILL.md":   filepath.Join(root, "plugins/bilimbi/skills/bilimbi/SKILL.md"),
		"plugins/bilimbi/bin/" + name:               binary,
		"INSTALL.md":                                filepath.Join(root, "clients/bilimbi-cli/README.md"),
		"LICENSE":                                   filepath.Join(root, "LICENSE"),
	}
	destinations := make([]string, 0, len(sources))
	for destination := range sources {
		destinations = append(destinations, destination)
	}
	sort.Strings(destinations)
	for _, destination := range destinations {
		source := sources[destination]
		data, e := os.ReadFile(source)
		if e != nil {
			z.Close()
			file.Close()
			return e
		}
		header := &zip.FileHeader{Name: destination, Method: zip.Deflate}
		header.SetModTime(time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC))
		header.SetMode(0644)
		if destination == "plugins/bilimbi/bin/"+name {
			header.SetMode(0755)
		}
		entry, e := z.CreateHeader(header)
		if e == nil {
			_, e = entry.Write(data)
		}
		if e != nil {
			z.Close()
			file.Close()
			return e
		}
	}
	marketplace := map[string]any{"name": "bilimbi-local", "interface": map[string]string{"displayName": "Bilimbi"}, "plugins": []any{map[string]any{"name": "bilimbi", "source": map[string]string{"source": "local", "path": "./plugins/bilimbi"}, "policy": map[string]string{"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Productivity"}}}
	header := &zip.FileHeader{Name: ".agents/plugins/marketplace.json", Method: zip.Deflate}
	header.SetMode(0644)
	header.SetModTime(time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC))
	entry, err := z.CreateHeader(header)
	if err == nil {
		err = json.NewEncoder(entry).Encode(marketplace)
	}
	if err == nil {
		var notices []byte
		notices, err = licenses(binary)
		if err == nil {
			noticeHeader := *header
			noticeHeader.Name = "THIRD_PARTY_NOTICES.txt"
			entry, err = z.CreateHeader(&noticeHeader)
			if err == nil {
				_, err = entry.Write(notices)
			}
		}
	}
	if closeErr := z.Close(); err == nil {
		err = closeErr
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	f, err := os.Open(output)
	if err != nil {
		return err
	}
	defer f.Close()
	sum := sha256.New()
	if _, err = io.Copy(sum, f); err != nil {
		return err
	}
	return os.WriteFile(output+".sha256", []byte(hex.EncodeToString(sum.Sum(nil))+"  "+filepath.Base(output)+"\n"), 0644)
}

// Read the executable's own module metadata, so each target includes notices
// for the dependencies it actually ships rather than a second dependency list.
func licenses(binary string) ([]byte, error) {
	info, err := buildinfo.ReadFile(binary)
	if err != nil {
		return nil, fmt.Errorf("cannot read binary dependency metadata: %w", err)
	}
	goLicense, err := os.ReadFile(filepath.Join(runtime.GOROOT(), "LICENSE"))
	if err != nil {
		return nil, err
	}
	var result bytes.Buffer
	fmt.Fprintf(&result, "Go %s\n\n%s\n", info.GoVersion, goLicense)
	for _, dependency := range info.Deps {
		if dependency.Replace != nil {
			return nil, fmt.Errorf("release binary contains a replaced dependency")
		}
		command := exec.Command(filepath.Join(runtime.GOROOT(), "bin", "go"), "list", "-m", "-json", dependency.Path)
		data, err := command.Output()
		if err != nil {
			return nil, fmt.Errorf("cannot locate license for %s", dependency.Path)
		}
		var module struct{ Dir, Version string }
		if json.Unmarshal(data, &module) != nil || module.Dir == "" || module.Version != dependency.Version {
			return nil, fmt.Errorf("dependency version mismatch for %s", dependency.Path)
		}
		found := false
		for _, name := range []string{"LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING"} {
			license, err := os.ReadFile(filepath.Join(module.Dir, name))
			if err == nil {
				fmt.Fprintf(&result, "\n%s %s\n\n%s\n", dependency.Path, dependency.Version, strings.TrimSpace(string(license)))
				found = true
				break
			}
		}
		if !found {
			return nil, fmt.Errorf("license missing for %s", dependency.Path)
		}
	}
	return result.Bytes(), nil
}
