package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestPackExecutableAndMarketplace(t *testing.T) {
	executablePath, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	binaryData, err := os.ReadFile(executablePath)
	if err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	for _, target := range []string{"windows-amd64", "darwin-arm64", "darwin-amd64", "linux-amd64"} {
		t.Run(target, func(t *testing.T) {
			dir := t.TempDir()
			binary := filepath.Join(dir, "binary")
			if err := os.WriteFile(binary, binaryData, 0755); err != nil {
				t.Fatal(err)
			}
			output := filepath.Join(dir, "plugin.zip")
			if err := pack(root, binary, target, output); err != nil {
				t.Fatal(err)
			}
			archive, err := zip.OpenReader(output)
			if err != nil {
				t.Fatal(err)
			}
			defer archive.Close()
			files := map[string]*zip.File{}
			for _, f := range archive.File {
				files[f.Name] = f
			}
			manifest := files["plugins/bilimbi/plugin.json"]
			if manifest == nil {
				t.Fatal("manifest missing")
			}
			reader, err := manifest.Open()
			if err != nil {
				t.Fatal(err)
			}
			var plugin struct {
				Name       string
				Version    string
				Extensions map[string]struct {
					OnboardingSkill string `json:"onboardingSkill"`
				}
			}
			err = json.NewDecoder(reader).Decode(&plugin)
			reader.Close()
			if err != nil || plugin.Name != "bilimbi" || plugin.Version == "" {
				t.Fatal("invalid plugin manifest")
			}
			onboarding := plugin.Extensions["com.openai"].OnboardingSkill
			if onboarding != "./skills/setup/SKILL.md" || files["plugins/bilimbi/"+onboarding[2:]] == nil {
				t.Fatal("setup cannot resolve its packaged skill")
			}
			compatibility := files["plugins/bilimbi/.codex-plugin/plugin.json"]
			if compatibility == nil {
				t.Fatal("compatibility manifest missing")
			}
			reader, err = compatibility.Open()
			if err != nil {
				t.Fatal(err)
			}
			var overlay struct{ Name, Version, Skills string }
			err = json.NewDecoder(reader).Decode(&overlay)
			reader.Close()
			if err != nil || overlay.Name != plugin.Name || overlay.Version != plugin.Version || overlay.Skills != "./skills/" {
				t.Fatal("compatibility manifest cannot discover the same plugin skills")
			}
			catalog := files[".agents/plugins/marketplace.json"]
			if catalog == nil {
				t.Fatal("catalog missing")
			}
			reader, err = catalog.Open()
			if err != nil {
				t.Fatal(err)
			}
			var marketplace struct {
				Plugins []struct {
					Name   string
					Source struct{ Path string }
					Policy struct{ Authentication string }
				}
			}
			err = json.NewDecoder(reader).Decode(&marketplace)
			reader.Close()
			if err != nil || len(marketplace.Plugins) != 1 || marketplace.Plugins[0].Source.Path != "./plugins/bilimbi" || marketplace.Plugins[0].Policy.Authentication != "ON_USE" {
				t.Fatal("catalog cannot resolve plugin")
			}
			name := "bilimbi"
			if target == "windows-amd64" {
				name += ".exe"
			}
			executable := files["plugins/bilimbi/bin/"+name]
			if executable == nil || executable.Mode().Perm() != 0755 {
				t.Fatal("executable missing or permissions lost")
			}
			reader, err = executable.Open()
			if err != nil {
				t.Fatal(err)
			}
			data, _ := io.ReadAll(reader)
			reader.Close()
			if !bytes.Equal(data, binaryData) {
				t.Fatal("binary corrupted")
			}
			if files["plugins/bilimbi/skills/bilimbi/SKILL.md"] == nil || files["INSTALL.md"] == nil || files["THIRD_PARTY_NOTICES.txt"] == nil || files["LICENSE"] == nil {
				t.Fatal("skill/install missing")
			}
			if _, err = os.Stat(output + ".sha256"); err != nil {
				t.Fatal("checksum missing")
			}
		})
	}
}
