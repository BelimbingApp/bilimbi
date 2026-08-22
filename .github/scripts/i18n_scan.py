#!/usr/bin/env python3
"""
i18n_scan.py — inventory of bare user-facing string literals not wrapped in Gettext.

Report mode only (issue #681, step 2). It prints a per-module inventory of
user-facing string literals that are NOT wrapped in a `gettext(...)` family call,
so the i18n backlog can be sized against real data. It has NO CI wiring and never
fails a build; the step-1 gate (fail-on-new) reuses the same detection later.

The detection is a heuristic, deliberately biased to UNDER-report: it flags
high-confidence user-facing positions exactly, and reports visible template text
as a separate, approximate SAMPLED bucket that a reader must still judge. A
per-module conversion PR is "done" for this tool when its HIGH count reaches zero.

Buckets
  HIGH     page titles, flash messages, and user-facing HEEx attributes
           (label/placeholder/title/caption/description/prompt/phx-disable-with/
           aria-label/alt). Almost always genuine user-facing copy; the reliable
           floor of the backlog.
  SAMPLED  visible text nodes in templates (~H blocks and .heex). Higher volume,
           noisier; reported as an approximate count with samples, not a claim.

Excluded: anything already inside gettext(/dgettext(/ngettext(; test files
(*_test.exs, /test/, /support/), /priv/, /docs/, and the Gettext backend modules.

Usage:
  .github/scripts/i18n_scan.py                 full report
  .github/scripts/i18n_scan.py --samples 5     N sample locations per module (HIGH)
  .github/scripts/i18n_scan.py --dump-high      every HIGH hit, one per line (for spot-checks)
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict

APPS = "apps"

# --- user-facing HEEx attributes: value is shown to a person -------------------
UF_ATTRS = (
    "label",
    "placeholder",
    "title",
    "caption",
    "description",
    "prompt",
    "phx-disable-with",
    "aria-label",
    "alt",
)
# `label="Copy"` but not `label_class="..."` (no `=` right after the name) and not
# `label={gettext("...")}` (that is `{`, not `"`, so it never matches).
ATTR_RE = re.compile(
    r'(?<![\w-])(' + "|".join(a.replace("-", r"\-") for a in UF_ATTRS) + r')="([^"]*)"'
)

# `assign(:page_title, "Sign in")` / `assign(socket, :page_title, "Sign in")`;
# the `gettext("...")` form puts `gettext(` before the quote, so it never matches.
PAGE_TITLE_RE = re.compile(r':page_title\s*,\s*"([^"]+)"')

# `put_flash(socket, :error, "…")` bare; the gettext form is excluded the same way.
PUT_FLASH_RE = re.compile(r'put_flash\([^)]*?,\s*:\w+\s*,\s*"([^"]+)"')

# A value only counts as copy if it contains a run of letters. This drops CSS-ish
# tokens ("mb-0"), icon names on alt="", ids, and empty attributes.
HAS_WORD = re.compile(r"[A-Za-z]{2,}")

# Pure-technical HEEx-attr values that are not translatable copy even in a
# user-facing attribute (icon names, sizing utilities used as sr-only labels are
# still copy, so we only drop obvious icon/class shapes).
TECH_VALUE = re.compile(r"^(hero-[a-z0-9-]+|[a-z0-9]+(-[a-z0-9]+)+)$")


def module_of(path: str) -> str:
    """apps/web/lib/... -> 'web'; apps/base/ui/lib/... -> 'base/ui'."""
    parts = path.split(os.sep)
    try:
        i = parts.index(APPS)
        seg = parts[i + 1 : parts.index("lib", i)]
        return "/".join(seg) if seg else parts[i + 1]
    except (ValueError, IndexError):
        return path


def excluded(path: str) -> bool:
    p = path.replace(os.sep, "/")
    return (
        "/test/" in p
        or "/support/" in p
        or "/priv/" in p
        or "/docs/" in p
        or p.endswith("_test.exs")
        or p.endswith("gettext.ex")
        or "/_build/" in p
        or "/deps/" in p
    )


def iter_files():
    """Every .ex/.heex under an apps/*/lib tree, minus the excluded paths."""
    for root, dirs, files in os.walk(APPS):
        dirs[:] = [d for d in dirs if d not in ("_build", "deps")]
        for name in files:
            if name.endswith((".ex", ".heex")):
                path = os.path.join(root, name)
                if f"{os.sep}lib{os.sep}" in path and not excluded(path):
                    yield path


def strip_markup(line: str) -> str:
    """Remove tags <...> and expressions {...} to expose visible text residue."""
    line = re.sub(r"<[^>]*>", " ", line)
    line = re.sub(r"\{[^}]*\}", " ", line)
    return line.strip()


def scan_file(path: str):
    """Return (high_hits, sampled_hits, gettext_calls) for one file.

    high_hits: list of (lineno, kind, text); sampled_hits: list of (lineno, residue)
    """
    high = []
    sampled = []
    gettext_calls = 0
    in_heex = False  # inside a ~H""" block
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()

    is_heex_file = path.endswith(".heex")
    for n, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        gettext_calls += len(re.findall(r"\b[dn]?gettext\(", line))

        # track ~H""" ... """ blocks in .ex for SAMPLED text context
        if not is_heex_file:
            if not in_heex and "~H\"\"\"" in line:
                in_heex = True
                continue
            if in_heex and line.strip() == '"""':
                in_heex = False
                continue

        heex_context = is_heex_file or in_heex

        # HIGH: page_title + put_flash (Elixir code, whole file)
        for m in PAGE_TITLE_RE.finditer(line):
            high.append((n, "page_title", m.group(1)))
        for m in PUT_FLASH_RE.finditer(line):
            high.append((n, "put_flash", m.group(1)))

        # HIGH: user-facing HEEx attributes (only meaningful in markup, but the
        # `attr="..."` shape does not occur in ordinary Elixir, so scan anywhere)
        for m in ATTR_RE.finditer(line):
            attr, val = m.group(1), m.group(2)
            if HAS_WORD.search(val) and not TECH_VALUE.match(val.strip()):
                high.append((n, attr, val))

        # SAMPLED: visible text nodes in template context. HEEx tags routinely
        # span several lines, so a line-based residue that still carries `=`, `<`
        # or `>` is an attribute or tag fragment, not visible text — excluding
        # those chars drops the multi-line-tag noise the naive strip leaves
        # behind (measured: 24/25 of the noise, keeping real copy like
        # "Back to sign in"). Still approximate: a reader confirms each per module.
        if heex_context:
            residue = strip_markup(line)
            if (
                residue
                and HAS_WORD.search(residue)
                and not any(c in residue for c in '=<>{}|@"~')
                and not residue.startswith(("<%", "<!--"))
                and not re.fullmatch(r"[A-Za-z]{1,3}", residue)
            ):
                sampled.append((n, residue))

    return high, sampled, gettext_calls


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=3, help="HIGH sample locations per module")
    ap.add_argument("--dump-high", action="store_true", help="print every HIGH hit for spot-checks")
    ap.add_argument("--dump-sampled", action="store_true", help="print every SAMPLED residue for spot-checks")
    args = ap.parse_args()

    per_mod_high = defaultdict(list)  # module -> [(path, line, kind, text)]
    per_mod_sampled = defaultdict(list)  # module -> [(path, line, residue)]
    per_mod_gettext = defaultdict(int)

    for path in sorted(iter_files()):
        high, sampled, gettext_calls = scan_file(path)
        mod = module_of(path)
        per_mod_gettext[mod] += gettext_calls
        for (n, kind, text) in high:
            per_mod_high[mod].append((path, n, kind, text))
        for (n, residue) in sampled:
            per_mod_sampled[mod].append((path, n, residue))

    if args.dump_high:
        for mod in sorted(per_mod_high):
            for (path, n, kind, text) in per_mod_high[mod]:
                print(f"{path}:{n}\t{kind}\t{text}")
        return
    if args.dump_sampled:
        for mod in sorted(per_mod_sampled):
            for (path, n, residue) in per_mod_sampled[mod]:
                print(f"{path}:{n}\t{residue}")
        return

    mods = sorted(set(per_mod_high) | set(per_mod_sampled) | set(per_mod_gettext))
    total_high = sum(len(v) for v in per_mod_high.values())
    total_sampled = sum(len(v) for v in per_mod_sampled.values())
    total_gettext = sum(per_mod_gettext.values())

    print("i18n inventory — bare user-facing literals not wrapped in Gettext (report mode)\n")
    print(f"{'module':<26}{'HIGH':>6}{'SAMPLED':>9}{'gettext()':>11}")
    print("-" * 52)
    for mod in mods:
        h = len(per_mod_high.get(mod, []))
        s = len(per_mod_sampled.get(mod, []))
        g = per_mod_gettext.get(mod, 0)
        if h or s or g:
            print(f"{mod:<26}{h:>6}{s:>9}{g:>11}")
    print("-" * 52)
    print(f"{'TOTAL':<26}{total_high:>6}{total_sampled:>9}{total_gettext:>11}\n")

    if args.samples:
        print(f"HIGH samples (up to {args.samples} per module):\n")
        for mod in mods:
            hits = per_mod_high.get(mod, [])
            if not hits:
                continue
            print(f"[{mod}]  ({len(hits)} HIGH)")
            for (path, n, kind, text) in hits[: args.samples]:
                snippet = text if len(text) <= 60 else text[:57] + "..."
                print(f"    {path}:{n}  {kind}: {snippet!r}")
            print()


if __name__ == "__main__":
    main()
