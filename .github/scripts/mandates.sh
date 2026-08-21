#!/usr/bin/env bash
# AGENTS.md declares these defect classes greppable; this gate makes the greps
# mechanisms (docs/ai-team/README.md: a rule that is not a mechanism is a rule
# you will break). Run from the repository root: .github/scripts/mandates.sh
#
# Output is captured per check and the exit code is computed explicitly, so no
# pipeline can mask a failure.

set -u

fail=0

# --- AGENTS.md §12: raw palette classes outside the @theme block -------------
# The @theme block in apps/web/assets/css/app.css is the only place a color is
# chosen; components and templates use the semantic roles it declares.
palette_hits=$(grep -rnE \
  '\b(bg|text|border|ring|shadow|divide|accent)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]+' \
  apps/*/lib apps/*/*/lib 2>/dev/null || true)

if [ -n "$palette_hits" ]; then
  echo "FAIL AGENTS.md §12 — raw palette class; use the semantic roles from @theme:"
  echo "$palette_hits"
  fail=1
fi

# --- AGENTS.md §13: hand-written tenant_id comparisons -----------------------
# Caller-facing reads must begin with Tenancy.scope_query/2. The allowlisted
# files hold the sanctioned exceptions the section describes: scope_query/2
# itself, and Core Company's owner-module row-lock/invariant reads (#544).
# Extending this allowlist is a review decision, made in the same change that
# adds the match.
tenant_allow='^apps/base/tenancy/lib/tenancy\.ex:|^apps/core/company/lib/company\.ex:|^apps/core/company/lib/company/primary_company_manager\.ex:'
tenant_hits=$(grep -rnE 'tenant_id\s*==\s*\^' apps/*/lib apps/*/*/lib 2>/dev/null |
  grep -vE "$tenant_allow" || true)

if [ -n "$tenant_hits" ]; then
  echo "FAIL AGENTS.md §13 — raw tenant filter outside the sanctioned owner-module sites:"
  echo "$tenant_hits"
  echo "Begin the read with Tenancy.scope_query/2."
  fail=1
fi

# --- AGENTS.md §7: String.to_atom/1 ------------------------------------------
# Atoms are never reclaimed, so nothing derived from request or user input may
# become one. Guarded String.to_existing_atom/1 (membership check first) is the
# approved pattern; String.to_atom/1 has no approved use in lib code.
atom_hits=$(grep -rn 'String\.to_atom(' apps/*/lib apps/*/*/lib 2>/dev/null || true)

if [ -n "$atom_hits" ]; then
  echo "FAIL AGENTS.md §7 — String.to_atom/1 in lib code:"
  echo "$atom_hits"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "mandates: §7, §12, §13 clean"
fi

exit "$fail"
