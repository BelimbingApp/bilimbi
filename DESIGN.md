---
version: stable
name: Bilimbi
description: Professional, compact, warm workflow UI for long operational sessions.
---

# DESIGN.md

## Overview

Bilimbi should feel professional, compact, warm, and trustworthy. It is
workflow software for long sessions: dense enough for operations, calm enough
for judgment, and polished enough that users trust it.

Success means users finish real work faster and leave—not that they spend more
time in the application. The interface is the brand: deliberate product
software with intentional taste, not a marketing site, consumer novelty, or
generic enterprise gray.

Less is more, but better. Every surface, label, and control must earn its
place.

Before designing a page, ask what can be removed, what should be obvious, what
should not be configurable, and where the page can feel more like a confident
product than a pile of components.

## Product character

Two choices define the Bilimbi look:

1. **The workspace strip.** No screen is context-free. The login card names
   the platform workspace being entered (live provisioning state included);
   the authenticated shell's top strip always names the company and tenant
   the screen acts on. Tenancy is visible product truth, not hidden plumbing.
2. **Ledger geometry.** Compact scale with `rounded-md` controls and
   `rounded-xl` surfaces, hairline rules, and tabular numerals for IDs and
   counts. The lime `brand` marks orientation only — the card's top edge,
   the active navigation highlighting, selection — and never reports status.
   The surface is ruled paper with a bookmark.

## Semantic color roles

Use semantic roles rather than arbitrary colors. The visual language should
have a warm operational base, a clear accent for primary actions, and honest
status colors for real feedback.

Keep color tokens and reusable theme rules in the shared web foundation. A
module may add a semantic role only when its workflow genuinely needs one.

- **`canvas` / `surface` / `surface-sidebar`**: Warm stone operational base.
- **`surface-sunken` (`#eaebe4`)**: Muted sunken surface used for table headers, code blocks, and subtle containers.
- **`brand-surface` (`#f3f5e8`)**: Subtle warm brand tint used on the pinned
  navigation surface and highlight containers.
- **`link` (`#544c43`) / `muted` (`#6b6057`) / `ink` (`#2c2418`)**: Warm font
  hierarchy for navigation links, secondary labels, and active hover text.
- **`brand-strong` (`lime-600`)**: Orientation accent for active navigation,
  ascended parent branches, and brand selection.

## Compact typography

The platform uses `Instrument Sans` globally as `--font-sans`. Use compact,
competent typography with enough contrast and line height for long sessions.
Use tabular numerals where users compare amounts, dates, counts, or measurements.

- **Global font:** `Instrument Sans` across all app views, forms, tables, and chrome.
- **Menu typography:** Scoped compact styling with thinner weight (`350` / `400`),
  `0.8125rem` (`13px`) font size, and `1.25rem` line height.
- Typography should support scanning before reading. Avoid decorative type that
  competes with operational content.

## Compact layout

Prefer high-signal layouts that remain usable on narrow screens. Compact does
not mean cramped:

- keep related controls close;
- preserve visible hierarchy and breathing room;
- make the primary action clear;
- keep tables readable without forcing unnecessary navigation;
- use responsive layouts instead of a separate mobile product.

Page content width is a shared decision, not a per-screen one. Every screen
wraps its content in the `<.page>` component and lets its variant choose the
width: `:list` for operational index screens, `:form` for single-column edit
forms, `:detail` for show screens and the dashboard. Never hand-write
`mx-auto max-w-*` on a screen's root container.

## Data tables & row density

Operational tables use compact, dense geometry for high-information density
during long operational sessions:

- **Row padding:** `py-0.5` (`0.125rem` / `2px`), `px-2` (`0.5rem` / `8px`) horizontal cell padding.
- **Header padding:** `py-1.5` (`0.375rem` / `6px`), `px-2` horizontal header padding.
- **Header background:** `bg-surface-sunken` (`#eaebe4`).
- **Header typography:** Proper case `text-xs font-semibold text-muted` (`text-ink-subtle`).
- **Body typography:** `text-sm text-ink`, with `tabular-nums text-muted` (`text-ink-muted`) for codes, IDs, currencies, phones, populations, dates, and measurements.
- **Search & filter cards:** Search inputs live in an outer `<.card>` container with `p-2` and a distinct bottom gap (`mb-2`) before the table headers begin, preventing search inputs from gluing directly to table headers.
- **Pagination controls:** Rows per page selector uses compact geometry (`w-14`, `h-7`, `pl-2 pr-4`) with accent focus styling (`focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30`). Navigation buttons use `size-7` with accent focus rings (`focus-visible:ring-1 focus-visible:ring-brand-strong/40`) and active page highlight (`border-brand-line bg-brand-surface text-brand-ink`).

## Inline editing

Inline editing allows quick modifications to entity fields without leaving the
table view:

- **Display mode:** Shows the field value in `text-ink` alongside a subtle hover pencil icon (`size-3.5 text-muted opacity-0 group-hover:opacity-100 transition-opacity`).
- **Activation:** Clicking the cell or pressing Enter when focused activates edit mode.
- **Editing mode:** Replaces the cell with an inline `<input>` styled with `border-action` / `border-brand-strong`, autofocusing and selecting the text.
- **Save & Cancel:** Pressing `Enter` or blurring saves the field, updates the LiveView stream item (`stream_insert/3`), clears edit state, and flashes feedback (`"<Entity> saved."`). Pressing `Escape` cancels editing and reverts to display mode.

## Subtle depth and motion

Use contrast, borders, and shadows with restraint. Motion should clarify state,
continuity, or completion at roughly 60fps. It must not delay work or create
attention noise.

Use Phoenix and LiveView loading states honestly. Users should know when work is
in flight, waiting, blocked, or complete.

## Reuse components

Reuse shared `BilimbiWeb.CoreComponents` and layout components before inventing
new markup. Shared components belong in the web foundation; workflow-specific
presentation, documentation, and optional assets belong inside the owning
deep-module directory even when the Phoenix host adapts them into routes or
layouts.

Use the shared `<.icon>` component for icons. Do not call Heroicons modules
directly from templates.

Use the shared `<.input>` and `<.form>` components for forms where available.
Keep forms driven by a `to_form/2` assign and give important forms and controls
stable DOM IDs for tests and accessibility.

Function components are the default reuse mechanism. Use a LiveComponent only
when it needs its own state and event lifecycle; do not introduce one merely to
split markup into another file.

## Application shell

Two shells exist and each stays minimal:

- **`Layouts.auth`** — the centered credential layout for sign-in and password
  recovery. One quiet card with the brand bar, the wordmark above it, and the
  workspace strip below. No navigation, no marketing.
- **`Layouts.app`** — the authenticated workspace shell: a compact full-width
  top bar (sidebar toggle, transparent `size-6` brand mark, Bilimbi wordmark,
  tenant on the right), a left menu sidebar, and a persistent status bar
  (application version). In development only, the status bar shows `dev` plus
  the listen address. Wide screens keep the rail; the collapsed rail hides
  labels and logout, leaving the user initials. Below `lg`, the menu is an
  off-canvas drawer. The logo is the product mark on a transparent background
  — never a brand tile.

### Navigation menu conventions

- **Typography & Font:** `Instrument Sans`, `0.8125rem` (`13px`), normal/light weight (`350`),
  `text-link` (`#544c43`), hover `text-ink` (`#2c2418`).
- **Chevrons:** Triangular chevrons `&#x2BC8;` (`⯈`) for collapsed branches,
  `&#x2BC6;` (`⯆`) for expanded branches, with figure space `&#8199;` indentation
  for leaf items.
- **Active Navigation:** Selected route uses card surface background (`bg-surface`),
  lime accent text (`text-brand-strong`), no bolding, and no spine border.
- **Parent Ascent:** All ancestor parent branches containing the active page accent
  their labels, toggles, and chevrons in `text-brand-strong`.
- **Pinned Surface:** Pinned container uses `bg-brand-surface` (`#f3f5e8`) with
  `rounded-sm` and `text-muted` (`#6b6057`) uppercase section header.
- **Ordering:** Menu roots and submenus are sorted strictly alphabetically ascending
  (`ASC`, case-insensitive).

The shell does not grow navigation items for pages that do not exist. A
workflow joins the sidebar when its screen ships, not before. Notifications,
theme, timezone, chat, and diagnostics controls appear only when a real
route or API backs them.

## Gestalt grouping

- **Proximity:** related controls and labels stay close.
- **Similarity:** the same role shares look and behavior.
- **Common region:** related work lives inside one clear surface.
- **Visual hierarchy:** the primary path reads first at a glance.

## Scan before reading

Users scan before they read. Favor headings, short action labels, badges,
counts, meaningful icons, and clear table structure.

- Design the scan layer first.
- Do not explain what a visible label, icon, badge, column, or state already
  says.
- Put safety or mode information in the control when it changes the decision,
  such as **Read-only review**.
- Reserve sentences for consequences, exceptions, recovery, or unfamiliar
  concepts.
- Before shipping, perform a no-prose scan. If the next action or current state
  is unclear, improve the scan layer before adding explanatory copy.

## Put information where it acts

A page title describes the whole page and must remain true across tabs. Put
workflow-specific purpose, consequences, and guidance inside the tab or surface
where they affect the user's decision.

If page-level copy joins sibling workflows with “or”, split the copy at those
workflow boundaries.

## Stay consistent

Same thing, same look, same place. Reuse established patterns, placement, and
labels across modules. Variation needs a user-visible reason.

## Honest feedback

Users should always know what is happening and what happened. Show work in
flight, give every action a visible and timely response, and keep outcomes
honest and transparent. Never fail silently. An empty navigation is a
permission-denied state: say that no destinations are available and name
the recovery (an operator must assign a role), not a blank rail.

## Reduce anxiety

Calm software reduces anxiety. Do not manufacture urgency, FOMO, false
scarcity, badge spam, or engagement loops. Trust comes from steady, honest
state and clear recovery paths.

## Write for humans

Use plain, respectful operational language. Write for the person doing the
work, not for enterprise theatre or system internals.

## Accessibility and resilience

Design for keyboard use, readable contrast, visible focus, semantic structure,
and screen-reader comprehension. Loading, empty, error, disabled, and
permission-denied states are part of the design—not afterthoughts.

The page must remain understandable when JavaScript is unavailable or a LiveView
connection is temporarily interrupted. Preserve meaningful server-rendered
content and communicate reconnection states honestly.
