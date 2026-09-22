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

The defining Bilimbi visual choice is **ledger geometry**: compact scale with
`rounded-md` controls and
   `rounded-xl` surfaces, hairline rules, and tabular numerals for IDs and
   counts. The lime `brand` marks orientation only — the card's top edge,
   the active navigation highlighting, selection, and unseen-by-you markers
   (the aggregate unread count badge and the per-item unread dot) — and never
   reports status.
The surface is ruled paper with a bookmark.

## Semantic color roles

Use semantic roles rather than arbitrary colors. The visual language should
have a warm operational base, a clear accent for primary actions, and honest
status colors for real feedback.

Keep color tokens and reusable theme rules in the shared web foundation. A
module may add a semantic role only when its workflow genuinely needs one.

- **`canvas` / `surface` / `surface-sidebar`**: Warm stone operational base.
- **`surface-sunken`**: Muted sunken surface used for table headers, code
  blocks, and subtle containers.
- **`brand-surface`**: Subtle warm brand tint used on the pinned navigation
  surface and highlight containers.
- **`link` (`stone-700` light / `stone-300` dark) / `muted` (`stone-600`
  light / `stone-400` dark) / `ink`**: Warm font hierarchy for navigation
  links, secondary labels, and active hover text. Links remain visibly stronger
  than muted text in both themes.
- **`brand-strong` (`lime-600`)**: Orientation accent for active navigation,
  ascended parent branches, brand selection, and the aggregate unread count
  badge. `brand` carries the same orientation meaning on the per-item unread
  dot. Unseen-by-you markers are orientation, not status.
- **`high-contrast-line` / `line` / `low-contrast-line`**: Neutral structural
  lines derived from `ink` at decreasing transparency. Their contrast remains
  ordered against canvas, surface, sunken, muted, and sidebar backgrounds.
- **`action` / `action-hover` / `action-ink`**: Confident primary action
  colours used for primary buttons and page `<h1>` headings. The base remains
  distinct from its brighter hover in both themes.
- **`success` / `warning` / `danger`** (each with `-surface`, `-line`,
  `-ink`): Honest status roles for real feedback. A neutral statement has no
  status role of its own yet: an `:info` flash is painted with `success` and
  an `:info` alert stays on the neutral surface, because most of the
  product's `:info` messages report a completed write.

## Compact typography

The platform uses `Instrument Sans` globally as `--font-sans`. Use compact,
competent typography with enough contrast and line height for long sessions.
Use tabular numerals where users compare amounts, dates, counts, or measurements.

- **Global font:** `Instrument Sans` across all app views, forms, tables, and chrome.
- **Page headings:** `<h1>` titles use `text-action` to anchor the screen's
  operational scope with the platform's primary action colour.
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
`mx-auto max-w-*` on a screen's root container. Every create and edit form
renders at the `:form` width — related field pairs may share a row inside it
(the company create screen is the exemplar), but the page never widens to
fit more columns.

### Input controls

- **Geometry:** Fields use `rounded-md`, compact `py-1.5` vertical padding,
  and the smallest width that still fits their content. This applies equally
  to forms, filters, and inline work.
- **Focus:** Keyboard focus uses `brand-strong` for the border and ring. Focus
  is orientation, so it stays consistent across control types and themes.
- **Choice:** Use the simplest control that fits the value: text for genuinely
  open values, select for one short fixed list, multi-select for several listed
  choices, checkbox for one independent setting, and radio for two to five
  exclusive choices that should remain visible.

## Data tables & row density

Operational tables use compact, dense geometry for high-information density
during long operational sessions:

- **Row padding:** `py-0.5` (`0.125rem` / `2px`), `px-2` (`0.5rem` / `8px`) horizontal cell padding.
- **Header padding:** `py-1.5` (`0.375rem` / `6px`), `px-2` horizontal header padding.
- **Header background:** `bg-surface-sunken`.
- **Table geometry:** Table frames use flat angles, including their overflow wrapper. `Bilimbi.Base.UI.Components.table/1` enforces this: neither framing mode carries a radius and the component takes no attribute that can add one, so a rounded table can only come from hand-written markup. The card that frames a table is the same shape, so `card/1` enforces the other half: `inner_class` carrying `p-0` is read as the flat-corner signal and drops the radius, while any other card keeps it. The signal changes the corner and nothing else — the card still emits `p-2`, so those cards keep the 8px they render today, and the `p-2`/`p-0` cascade behind that is tracked as its own defect. Neither rule is a per-screen class.
- **Header typography:** Proper case `text-xs font-semibold text-ink-subtle`.
- **Body typography:** `text-sm text-ink`, with `tabular-nums text-muted` (`text-ink-muted`) for codes, IDs, currencies, phones, populations, dates, and measurements.
- **Search & filter toolbar:** Search and filters sit together in an open
  toolbar with `mb-2` above the table surface. Do not wrap the toolbar in a
  second card; the list is the common region.
- **Pagination controls:** Rows per page selector uses compact geometry (`w-auto`, `h-7`, `pl-2 pr-6`) — sized to its content, because the options run to three digits and a fixed `w-14` clipped even `25` behind the dropdown arrow (#304) with accent focus styling (`focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30`). Render page navigation only when another page exists. Navigation buttons use `size-7` with accent focus rings (`focus-visible:ring-1 focus-visible:ring-brand-strong/40`) and active page highlight (`border-selection-line bg-brand-surface text-brand-ink`). Operational lists reach all of this through `Bilimbi.Base.UI.Components.pagination/1` rather than a hand-rolled pager; the address list uses it, rows-per-page selector included, by captain decision, so that is settled rather than open.

## Inline editing

Inline editing allows quick modifications to entity fields without leaving the
table view:

- **Display mode:** Shows the field value in `text-ink` alongside a subtle hover pencil icon (`size-3.5 text-muted opacity-0 group-hover:opacity-100 transition-opacity`).
- **Activation:** Clicking the cell or pressing Enter when focused activates edit mode.
- **Editing mode:** Replaces the cell with an inline `<input>` styled with
  `border-brand-strong`, autofocusing and selecting the text.
- **Save & Cancel:** Pressing `Enter` or blurring saves the field, updates the LiveView stream item (`stream_insert/3`), clears edit state, and flashes feedback (`"<Entity> saved."`). Pressing `Escape` cancels editing and reverts to display mode.

## Modal dialogs

A short workflow that must finish or be abandoned before the screen continues
(attach an address, add an employee, edit a postcode) opens in the shared
`<.modal>`, never in hand-written overlay markup:

- **Semantics:** A native `<dialog>` opened as modal, named by its visible
  title (`aria-labelledby`) and, when it has one, described by its one-line
  description (`aria-describedby`), so a screen reader announces both.
- **Focus:** Focus enters the dialog when it opens, stays inside while it is
  open, and returns to the control that opened it when it closes. The page
  behind is inert to the keyboard and to assistive technology.
- **Closing:** `Escape` and the Cancel button are one action and reach the
  same server handler. Clicking the dimmed page does nothing: the dialog
  usually holds a form, and a stray click must not discard it.
- **Feedback:** Because the page behind is inert and the dialog paints above
  it in the top layer, an outcome raised while the dialog stays open renders
  inside it — a LiveView passes `flash`, and a panel renders its own notice in
  the dialog. Every dialog also carries its own connection banners, so a
  dropped websocket is still announced and dismissable while one is open. The
  layout's copy of whatever the dialog carries is hidden, so the same message
  never appears twice; a dialog that carries no `flash` copy leaves the
  layout's `:info` and `:error` in the DOM, dimmed behind the backdrop until it
  closes. Opening a
  dialog in a production workflow dismisses an earlier action's flash, so a
  message about finished work is neither announced as this dialog's own nor
  left stranded and unreadable behind the inert page; the Design Library
  specimen, which raises no flash of its own, deliberately dismisses none.
- **Geometry:** A `rounded-xl` surface at `max-w-lg` for a single-column form
  or `max-w-2xl` for two columns, over an `ink/40` dimmer.

## Subtle depth and motion

Use contrast, borders, and shadows with restraint. Motion should clarify state,
continuity, or completion at roughly 60fps. It must not delay work or create
attention noise.

Motion is opt-out at the platform, not per component. A single
`prefers-reduced-motion: reduce` rule in `apps/web/assets/css/app.css` collapses
every CSS transition and animation to one frame, so anyone whose operating
system asks for reduced motion gets a still product wherever the motion is CSS.
Components and templates do not carry their own `motion-reduce` variants.

One known exception is outstanding: the vendored `topbar` navigation progress
bar paints itself onto a canvas from JavaScript, so no CSS duration reaches it
and it still slides and fades under reduce. Teaching it the preference without
losing an honest loading signal is open parity work under FND-05.

Use Phoenix and LiveView loading states honestly. Users should know when work is
in flight, waiting, blocked, or complete.

## Reuse components

Reuse shared `Bilimbi.Base.UI.Components` and layout components before inventing
new markup. Shared components belong in Base UI; workflow-specific
presentation, documentation, and optional assets belong inside the owning
deep-module directory even when the Phoenix host adapts them into routes or
layouts.

Use the shared `<.icon>` component for icons. Do not call Heroicons modules
directly from templates. For an action that has a direct Belimbing equivalent,
use the same established icon choice so replacement does not make familiar
actions harder to recognize. Render it through Bilimbi's icon registry rather
than copying assets or framework markup. Logout is the explicit exception and
keeps Bilimbi's own treatment.

Use `<.icon_button>` for familiar repeated secondary actions where words would
create table or toolbar noise. Inline controls are `size-6` (24px targets); table and toolbar
controls are `size-7`. Every icon-only action has an accessible label and title.
Keep primary and unfamiliar actions as words. Destructive actions use calm
danger text with quiet hover feedback, never a solid red button.

Use the shared `<.input>` and `<.form>` components for forms where available.
Keep forms driven by a `to_form/2` assign and give important forms and controls
stable DOM IDs for tests and accessibility.

Function components are the default reuse mechanism. Use a LiveComponent only
when it needs its own state and event lifecycle; do not introduce one merely to
split markup into another file.

## Application shell

Two shells exist and each stays minimal:

- **`Layouts.auth`** — the centered credential layout for sign-in and password
  recovery. One quiet card with the brand bar and the wordmark above it. Name
  a workspace only when the user is genuinely choosing or entering a distinct
  workspace. No navigation, no marketing.
- **`Layouts.app`** — the authenticated workspace shell: a compact full-width
  top bar (sidebar toggle, transparent `size-6` brand mark and Bilimbi
  wordmark, current timezone selector and light/dark theme selector), a left
  menu sidebar, and a persistent status bar
  (application version). In development only, the status bar shows `dev` plus
  the listen address. Wide screens keep the rail; the collapsed rail hides
  labels, leaving the user initials. The bottom-left user circle remains the
  account entry point in both states. Activating it opens a compact menu with
  the signed-in name and identifier, current company and tenant, change
  password, and sign out. Offer scope switching only when the user has more
  than one permitted scope. Below `lg`, the menu is an off-canvas drawer. The
  logo is the product mark on a transparent background — never a brand tile.

Ordinary users do not need company and tenant repeated in the top strip. Show
an always-visible scope warning outside the account menu when context is
unusual or safety-critical, including platform-operator access, impersonation,
or cross-company work where acting in the wrong scope could cause harm.

The timezone and theme selectors are compact top-bar utilities, not settings
navigation. A selection applies immediately and persists for the signed-in
user. Both take effect on the current page without a reload: a theme change
restyles it, and a timezone change re-renders every timestamp rendered through
`<.datetime>`, streamed table rows included. Screens that format instants
directly rather than through that component are unaffected until they adopt
it.

### Navigation menu conventions

- **Typography & Font:** `Instrument Sans`, `0.8125rem` (`13px`), normal/light
  weight (`350`), `text-link` (`stone-700` light / `stone-300` dark), hover
  `text-ink`.
- **Chevrons:** Triangular chevrons `&#x2BC8;` (`⯈`) for collapsed branches,
  `&#x2BC6;` (`⯆`) for expanded branches, with figure space `&#8199;` indentation
  for leaf items.
- **Active Navigation:** Selected route uses card surface background (`bg-surface`),
  lime accent text (`text-brand-strong`), no bolding, and no spine border.
- **Parent Ascent:** All ancestor parent branches containing the active page accent
  their labels, toggles, and chevrons in `text-brand-strong`.
- **Pinned Surface:** Pinned container uses `bg-brand-surface` with `rounded-sm`
  and `text-muted` (`stone-600` light / `stone-400` dark) uppercase section
  header.
- **Ordering:** Menu roots and submenus are sorted strictly alphabetically ascending
  (`ASC`, case-insensitive).

The shell does not grow navigation items for pages that do not exist. A
workflow joins the sidebar when its screen ships, not before. Notifications,
chat, and diagnostics controls appear only when a real route or API backs
them.

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

Flash messages stack at the top right, most severe first, so several stay
readable at once. Info, warning and error stay until the person dismisses
them, because a message someone must act on must not disappear on a timer.
Only a success times out, after eight seconds, and nothing emits one yet: the
timer waits on the confirmation callers that still use info.

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
