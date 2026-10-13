#!/usr/bin/env bash
# Run Sobelow for the host and every module package in one Mix VM. Sobelow
# needs each package's own root, but starting Mix once per root dominated scan
# time without changing the findings.
set -euo pipefail

exec mix run --no-start .github/scripts/sobelow_modules.exs
