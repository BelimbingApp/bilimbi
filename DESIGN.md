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

## Relationship to Belimbing

Belimbing is the behavioral reference: its interaction contracts (neutral
credential errors, throttled retries, two-phase sign-in handoff, sidebar with
user footer) are preserved unless this document says otherwise. Bilimbi is
not a reskin. Two deliberate distinctions define the Bilimbi look:

1. **The workspace strip.** No screen is context-free. The login card names
   the platform workspace being entered (live provisioning state included);
   the authenticated shell's top strip always names the company and tenant
   the screen acts on. Tenancy is visible product truth, not hidden plumbing.
2. **Ledger geometry.** Compact scale with `rounded-md` controls and
   `rounded-xl` surfaces, hairline rules, and tabular numerals for IDs and
   counts. The lime `brand` marks orientation only — the card's top edge,
   the active navigation item's spine, selection — and never reports status.
   Where Belimbing is soft, arid, and pill-shaped, Bilimbi is ruled paper
   with a bookmark.

## Semantic color roles

Use semantic roles rather than arbitrary colors. The visual language should
have a warm operational base, a clear accent for primary actions, and honest
status colors for real feedback.

Keep color tokens and reusable theme rules in the shared web foundation. A
module may add a semantic role only when its workflow genuinely needs one.

## Compact typography

Use compact, competent typography with enough contrast and line height for long
sessions. Use tabular numerals where users compare amounts, dates, counts, or
measurements.

Typography should support scanning before reading. Avoid decorative type that
competes with operational content.

## Compact layout

Prefer high-signal layouts that remain usable on narrow screens. Compact does
not mean cramped:

- keep related controls close;
- preserve visible hierarchy and breathing room;
- make the primary action clear;
- keep tables readable without forcing unnecessary navigation;
- use responsive layouts instead of a separate mobile product.

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
- **`Layouts.app`** — the authenticated workspace shell. A compact sidebar
  carries the brand, the primary navigation (Dashboard, Companies, Users) with
  the active item marked by a brand spine, and the user footer with initials
  and logout. The top strip always names the workspace: company on the left,
  tenant on the right.

The shell does not grow navigation items for pages that do not exist. A
workflow joins the sidebar when its screen ships, not before.

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
honest and transparent. Never fail silently.

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
