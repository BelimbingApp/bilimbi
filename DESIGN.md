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
- **`success` / `info` / `warning` / `danger`** (each with `-surface`,
  `-line`, `-ink`): Honest status roles for real feedback. `info` is blue, as
  in Belimbing: a statement that informs without confirming a write, so an
  `:info` flash, alert or panel notice never looks like the `:success` a
  completed write reports. Each kind is announced by what it does: success
  and info are a polite `status`, warning and error an assertive `alert`.

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
fit more columns. A detail page shares the list width: Belimbing's
`admin/*/show` pages set no width of their own, so their cards fill the main
column beside the sidebar at every viewport, and a detail's sections carry
the same tables an index does. Inside a section, only prose keeps a reading
limit (`max-w-prose` on a description paragraph); the cards themselves fill.
The facts inside a section are the shared `<.list>` (see "Detail sections and
facts").

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
- **Table geometry:** Table frames use flat angles, including their overflow wrapper. `Bilimbi.Base.UI.Components.table/1` enforces this: neither framing mode carries a radius and the component takes no attribute that can add one, so a rounded table can only come from hand-written markup. A card is flat only where it is the table's frame — the full-bleed case where the card edge and the table edge are the same line — so `card/1` enforces the other half: `inner_class` carrying `p-0` is read as the flat-corner signal and drops the radius, while any other card keeps it, including a padded section card around an inset table. The card resolves its padding in Elixir before the classes reach the markup: a padding shorthand the caller passes replaces the `p-2` default rather than competing with it in the stylesheet, so a `p-0` card is padless and its table reaches the card edge. Neither rule is a per-screen class.
- **Header typography:** Proper case `text-xs font-semibold text-ink-subtle`.
- **Body typography:** `text-sm text-ink`, with `tabular-nums text-muted` (`text-ink-muted`) for codes, IDs, currencies, phones, populations, dates, and measurements.
- **Search & filter toolbar:** Search and filters sit together in an open
  toolbar with `mb-2` above the table surface. Do not wrap the toolbar in a
  second card; the list is the common region.
- **Pagination controls:** Rows per page selector uses compact geometry (`w-auto`, `h-7`, `pl-2 pr-6`) — sized to its content, because the options run to three digits and a fixed `w-14` clipped even `25` behind the dropdown arrow (#304) with accent focus styling (`focus:border-brand-strong focus:outline-none focus:ring-1 focus:ring-brand-strong/30`). Render page navigation only when another page exists. Navigation buttons use `size-7` with accent focus rings (`focus-visible:ring-1 focus-visible:ring-brand-strong/40`) and active page highlight (`border-selection-line bg-brand-surface text-brand-ink`). Operational lists reach all of this through `Bilimbi.Base.UI.Components.pagination/1` rather than a hand-rolled pager; the address list uses it, rows-per-page selector included, by captain decision, so that is settled rather than open. The audit action and mutation logs use it the same way: the rows-per-page selector lives in the component rather than the filter toolbar, the URL keeps each screen's own page-size key, and a single page shows the result count and the selector with no navigation, exactly as the address list does.
- **Record facts:** the read-only facts of one record — a detail summary, the System Info cards, the Language & Region provenance card — render through `<.list>`: one `<dl>`, label beside a left-aligned value (see "Detail sections and facts"), with an `id` on the list and on any value cell a test or an anchor must reach. A screen never hand-writes its own `<dl>` rows for that. A value the screen could not read says so in muted text (`text-ink-faint`) rather than disappearing.

## Inline editing

Inline editing allows quick modifications to entity fields without leaving the
surface they are read on — a table row or a detail page fact:

- **Display mode:** Shows the field value in `text-ink` alongside a subtle hover pencil icon (`size-3.5 text-muted opacity-0 group-hover:opacity-100 transition-opacity`). A blank value shows `—` in `text-ink-muted`.
- **Activation:** Clicking the cell or pressing Enter when focused activates edit mode.
- **Editing mode:** Replaces the cell with an inline `<input>` styled with
  `border-brand-strong`, autofocusing and selecting the text.
- **Save & Cancel:** Pressing `Enter` or blurring commits the field; pressing `Escape` cancels editing and reverts to display mode. An unchanged value commits nothing, and an emptied value commits nothing unless the owner passes `allow_empty`, so a nullable fact has to say so. In a list the owner updates the LiveView stream item (`stream_insert/3`).
- **Outcome on the field:** The hook never paints the typed value; the stored
  value stays on screen until the server confirms a change. The field reads
  "Saving…" and carries `aria-busy` for the round trip, then the owner's
  `status` renders the outcome where the operator typed: `:saved` as a
  `role="status"` line, `{:error, message}` as a `role="alert"` naming the
  rejected value and the validation error. A refused commit is never a
  silent revert, and a validation error never lands only in a flash.

## Detail sections and facts

A detail page is the page header followed by a stack of sections. Every
section has the same anatomy, so an operator reads `/companies/:id`,
`/addresses/:id` and the panels a page embeds (the company and employee
address panels) as one surface:

- **The section is a `<.card>`** with `inner_class="p-5 sm:p-6"`, a
  `role="region"` and an `aria-labelledby` naming its heading. Nothing
  hand-writes a rounded panel.
- **It opens with `<.section_heading>`**, the one heading treatment: a
  small-caps `<h2>` (`text-xs font-semibold uppercase tracking-wider
  text-ink-subtle`, the heading Belimbing's `admin/*/show` cards carry), an
  optional `count` badge, an optional `description` line, `title_actions`
  right beside the title (the demoted edit icon that opens a grouped editor)
  and `actions` at the end of the row (the section's "Manage" link or its own
  buttons). A hand-written `<h2>`/`<h3>` in a section body is a defect; so is
  a `<dt>` doing a heading's job.
- **Its facts are `<.list>`**: one row per fact, the label in a fixed
  `10rem` column and the value left-aligned in a cell that fills the rest of
  the row. The value cell can name itself (`<:item id="detail-name">`), and
  it is a block the width of the row, which is what lets `<.inline_edit>`
  open its input at full width and report "Saved" or its refusal underneath.
  A hand-written `<dl>` grid of facts is a defect. Facts that are not one
  line — a company's business activities, its metadata JSON, an address's raw
  input — are still rows of the same list, as Belimbing renders them.
- **Its table is `<.table framed={false}>`**, unframed because the card is
  the panel. The table is flat; the padded card keeps its radius, because
  the inset table does not touch the card edge.

The address panels follow the same anatomy inside their owner's page. Their
sort buttons are addressed to the panel through `sort_target={@myself}`, the
priority cell commits in place through `<.inline_edit>` (the hook addresses
its event to its own element, so it reaches the LiveComponent that rendered
the field, or the LiveView when none did), the kinds are a choice fact whose
read state is the trigger, and unlinking is a demoted `<.icon_button>` with
Belimbing's link-slash glyph. `/employees/:id` and `/users/:id` follow the
same anatomy: the employee's linked account is a row of its Employment
Information list whose value is the `employee.accounts` embed, its
subordinates are the shared table with assigning in the heading row and a
demoted remove action on the row; the user's roles and each domain of its
effective and denied permissions are rows of the same list, and its Employee
Records and External Accesses sections open with the shared heading. The
database-query console renders its result set through the same table, one
sort button per returned column. The departments and relationships pages
still hand-write their sections and adopt this anatomy as they are migrated,
and the two disclosure triggers on `/users/:id` (Effective Permissions,
Change Password) keep their hand-written heading until the shared disclosure
lands.

## Read-first detail pages

A detail page shows the record as facts and lets an authorized operator change
each fact in place. `/addresses/:id` is the exemplar, `/users/:id` the second
full adopter (its name, email and company), `/employees/:id` the third
(seven text facts and the department, supervisor, employee type and status
choices), `/companies/:id` the fourth (every Company Details fact, its
business activities and metadata, and its default timezone) and
`/employee-types/:id` the fifth (its label; the code is permanent). There is
no edit mode and no save button: a committed edit saves by itself, and an
"Edit …" button that opens a separate edit form for the same facts is a
defect.

**A record's page is read-first whether or not the codebase calls it a
detail page.** The rule is about the record, not the route name: a record
whose only page was an edit form — Belimbing gives an employee type no
`show`, so `admin/employee-types/{id}/edit` is that record's page — gets a
read-first record page at `/<records>/:id` in this same shape, at the detail
width, and the edit route is retired. Once a record's page edits in place, a
separate `/:id/edit` route for the same facts is a second surface for one
workflow, so a list's Edit action opens the record page; `/employees/:id/edit`,
`/employee-types/:id/edit` and `/users/:id/edit` are gone for that reason. The
`:form` width belongs to a genuine create form. What "committed"
means follows the control and is the same for every fact of that kind on the
page:

- **Text facts** use `<.inline_edit>` and commit on Enter or on leaving the
  field. Every nullable column passes `allow_empty`; a required column (a
  company's name and code) does not, so an emptied value commits nothing.
- **A fact that adds rather than edits** — a company's business activities,
  which Belimbing grows through a "+ Add" chip that opens an input committing
  on Enter or blur — is the same `<.inline_edit>` with an always-empty value
  and a `placeholder` naming the addition ("Add activity"), so the trigger
  says what committing it does instead of reading as an empty value. The
  fact reports adding and removing on that one control; removal stays on the
  chip.
- **Choice facts** show the read state (a badge, a name) as the trigger; the
  select appears on click, commits on change, and Escape or leaving it
  cancels. A permanently visible `<select>` beside read-only facts is a
  defect: the address verification status, the user's company, the
  employee's department, supervisor, employee type and status, and the
  company's status, legal entity type, jurisdiction, parent company and
  default timezone are the shipped choice facts. A fact that is a setting
  rather than a column — the company's default timezone, read and written
  through Base Settings — is still a choice fact of its own section and
  reads its explicit value to decide whether it is configured, as Belimbing's
  `explicitCompanyTimezone` does, and names beside an unset one the zone
  `Bilimbi.Base.DateTime` renders its dates in (company, then tenant, then
  platform default, UTC for an unconvertible value) — "Not configured
  (Asia/Kuala_Lumpur)" under a tenant-level zone, "Not configured (UTC)" only
  when the resolution ends at UTC. Belimbing always says UTC there, which is
  untrue under a tenant-level setting; Belimbing keeps that one control
  always visible with a saved note beside it, and Bilimbi's read-state
  trigger is the deliberate shape. A choice offers only values the product
  can stand behind: the user's company offers the workspace's live
  companies and no "None", because a user always belongs to a company and
  an account with none is reachable from no screen. Belimbing's select
  offers the blank and saves it on change; Bilimbi drops the option rather
  than guarding it with a confirmation, so the choice commits on change like
  every other. A change whose cost the operator cannot see — a company
  change ends every session the account holds — says so in the open editor,
  as a `text-warning-ink` note beside the select that the select's
  `aria-describedby` names, before the choice is made. Cost alone does not
  earn a second click; a note is the warning, and a confirmation is reserved
  for a choice that cannot be undone.
- **Interdependent facts** — the address location, where a country change
  invalidates the division, postcode and locality — commit together through
  one grouped editor with a primary Apply and a Cancel. The group is opened
  by a demoted `<.icon_button icon="edit" context={:inline}>` beside its
  heading — the `title_actions` slot of `<.section_heading>` — not by an
  "Edit …" button, and refused fields report on their own inputs. Use a
  group only where the facts genuinely change together; a group is not a way
  to bring back the edit mode.
- **A document fact** — a company's metadata JSON — is one multi-line value
  that Enter cannot commit and a half-typed document must not commit on
  blur, so it keeps the grouped editor's shape for a single fact: the demoted
  `<.icon_button icon="edit" context={:inline}>` beside the value opens a
  textarea with a primary Apply and a Cancel, Escape cancels, a refusal
  ("must be a JSON object") reports on the fact and keeps the editor open
  with what was typed, and an applied empty document clears the value. This
  is Belimbing's own shape for that fact, with its Save renamed to Apply.
- **Outcome per fact:** "Saving…" while in flight, "Saved" for the most recent
  commit only — any later write clears it, including one the server refuses,
  so no stale "Saved" stands beside a rejected form — and a refusal that stays
  on its fact until that fact is committed again. A success elsewhere never
  clears another fact's refusal. Success does not flash: the fact already says
  so. `Bilimbi.Base.UI.CommitStatus` owns this bookkeeping — the `:field_status`
  assign, which "Saved" stands, the refusal sentence and how much of a rejected
  value it repeats — and every adopter calls it; a page keeps only its own
  write, its failure nouns and its forbidden-flash wording.
- **Viewers without the update capability** see the value with no affordance,
  not a disabled control. Every write handler still re-asks Authz.
- **Facts the page cannot save stay read-only.** A relation another module
  owns (the employee's company), a date the text editor cannot commit
  truthfully (employment start and end) and a record with its own workflow
  (the linked account, subordinates, addresses) read as text or keep their
  own section; an edit affordance for something the page cannot actually
  save is a defect, not a step toward parity. The same rule covers a whole
  record no write can reach: a user whose company is archived shows every
  fact as text, offers no picker, password form, employee action or delete,
  and says why once, in a `<.alert kind={:warning}>` under the header that
  names what is prevented, states that archiving is final, and offers no
  step the product lacks. The
  write handlers keep refusing, so a forged commit is still met on its fact.
- **Record history** is a demoted labelled action in the header: the
  registry's `history` glyph (Belimbing's clock) beside the word "History",
  in the same quiet `text-link` treatment as the back link, as Belimbing's
  `admin/*/show` pages present it. The `record.history` panel renders it; a
  page never builds its own. The page passes the record itself as `record`
  beside the `auditable_id`: the id never changes, so it alone would never
  re-render the panel, and a trail that stands still after an in-page edit
  states something untrue. A timestamp inside a diff follows the page's
  clock like the entry's own time, and reads to the second so two changes
  inside one minute do not read as the same value.

## Demoted secondary actions

A page header's buttons are for the work the page is about. Returning to where
the operator came from is a secondary action and is always a plain link, never
a button: `<.back_link navigate={...}>` renders "← Back" in `text-link`, and its
`title` names the destination ("Back to company") when the page has more than
one way back. This holds for every page — list, form and detail — so a
"Back to …" `<.button>` anywhere is a defect. Record history is demoted the
same way: it is a labelled action in the header, never a button. A quiet
action that submits a request rather than navigating — Impersonate on
`/users/:id`, a `POST` — is an `<.action_link>` with `href` and `method`,
so a detail header reads as one labelled row: History, Impersonate, "← Back",
each glyph beside its word, and no button among them.

Reaching a related workflow is demoted too. A section that lists records
another page manages — a company's Departments and Relationships — carries
one `<.action_link>` ("Manage") in its own heading row, with the registry's
`manage` glyph, the cog Belimbing uses for the same action. When the related
workflow belongs to the whole page rather than one section, the link sits
beside the primary action instead: `/companies` reaches Department Types and
Legal Entity Types through `<.action_link>`, and `/employees` reaches Employee
Types the same way, so the only button each actions row carries is that page's
primary create action — and only for an actor permitted to create. In that row
the primary action comes first and the demoted related-workflow links follow
it, so an operator moving between `/companies` and `/employees` finds them on
the same side. The shared `<.header>` actions container is a plain block with
no gap, so a page header's actions row wraps its controls in a
`flex items-center gap-3` row at the call site — whether it holds a primary
action followed by demoted links (`/companies`, `/employees`) or only demoted
actions and record metadata (`/companies/:id`, `/addresses/:id`). Without it
the controls sit one collapsed space apart and read as a single run of text.
The page header never repeats a section's link as a button; on
`/companies/:id` its actions row holds the status badge, the history action
and the back link and no button, while the title row keeps the pin icon
action. Below the `sm` breakpoint the shared `<.header>` stacks the actions
row under the title, as Belimbing's page header does, so a labelled row never
squeezes the title into one word per line or clips at the viewport edge; the
call-site row is also `flex-wrap`, so a long row wraps rather than overflows. `<.action_link>` is the general form of `<.back_link>`: the same
`text-link` treatment, free text, and a registry glyph. A related-workflow
`<.button>` that is not the page's primary action is a defect.

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
- **Geometry:** A `rounded-xl` surface at `max-w-lg` for a single-column form,
  `max-w-2xl` for two columns or `max-w-md` for a confirmation, over an
  `ink/40` dimmer.

### Confirmation dialogs

An action that cannot be undone — deleting a reference type, unlinking an
address — confirms through `<.confirm_dialog>`, a `<.modal>` specialised for
one answer, never through the browser's own `data-confirm` dialog, which
cannot say what the consequence is, cannot be styled and reads as a browser
alert rather than part of the product. Belimbing's confirmation shows the
shape to keep — a short dialog, consequence copy, a cancel beside the
destructive verb — and the gaps to close: it moved no
focus, ignored Escape and painted its Delete solid red.

- **Consequence first:** the dialog's title is one sentence saying what will
  happen to the data ("Legal entity type “LLC” will be deleted."), so it is
  the dialog's accessible name and the first thing announced; the detail
  says what is kept and whether the change can be undone ("It can no longer
  be chosen for a company. This cannot be undone."). Neither asks a question.
  The dialog is an `alertdialog`, the role reserved for a message that needs
  an answer before anything else continues.
- **Two actions:** Cancel first, so it takes focus when the dialog opens and
  Enter, Escape and Cancel all keep the data as it is; then the confirm as a
  calm danger text control named by the verb alone ("Delete", "Unlink"). No
  typed acknowledgement: nobody retypes a name to prove they read the
  sentence above the button.
- **Ownership:** the caller holds the requested record in an assign, renders
  the dialog with `:if` while it is pending, acts on that held record from
  `on_confirm` rather than on a client-supplied id, and stops rendering the
  dialog whatever the outcome. The outcome then reports through the page's
  flash — a completed delete as `:success`, so it times out — or the panel's
  notice, and a refusal names what to do next ("one or more companies still
  use it. Change those companies' legal entity type first."). The confirm
  carries `phx-disable-with` for the round trip ("Deleting…").
- **Specimen:** the Design Library's Overlays section shows the whole flow —
  entry, consequence, in flight, success, failure and recovery — on example
  records, not only the resting dialog.

Every destructive control confirms this way: the reference-type deletes, the
address unlinks and deletes, the company relationship and department removals,
the business activity chip, the employee and employee type deletes, the
subordinate removal, the user deletes, the employee unlink, the role and
capability rule changes on `/users/:id`, the saved database query deletes, the
session terminate, the settings restore and the schedule pause and disable. No
`data-confirm` attribute remains in the product. The schedule's enable confirms
the same way, because it approves the definition under review to run
unattended: the dialog names the task and states that it begins running on its
schedule at that definition's fingerprint. Resume only lifts a pause and runs
on click, matching Belimbing, where a confirmation is reserved for a choice
that cannot be undone; discarding an unsaved database query is the same case.

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
than copying assets or framework markup; a two-state control names each state
(`retain` is Belimbing's outline bookmark on an audit row that is not kept,
`retained` the solid one on a row that is). Logout is the explicit exception
and keeps Bilimbi's own treatment.

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
  The bar is `h-7` with no vertical padding, so every control in it is the
  `size-6` inline size the sidebar toggle uses; a `size-7` control fills the
  bar and paints its pressed and hover surfaces onto the bar's border.

Ordinary users do not need company and tenant repeated in the top strip. The
strip above the workspace is for transient state with an exit: it renders only
while impersonating, carrying "Viewing as … · Stop". A standing fact about the
scope is not a strip. When the scope's tenant carries `is_platform_operator`,
the account menu shows a "Platform-operator" row below Tenant, in the strip's
own caution tokens (`warning-surface`, `warning-ink`, `warning-line`) with the
registry's `warning` glyph, so it still reads as a caution rather than a
neutral scope line. The row names the company's platform-operator status, not
a personal entitlement: an account in that company may still be refused the
operator-only surfaces, which is why it is not worded as ownership. Nothing
about it changes what any capability or impersonation guard permits.

The operator-only surfaces carry their own caution, on the screen, where an
action or a listing is genuinely not filtered to one company. It uses the same
`warning` tokens and says what is unfiltered, never who the operator is: the
account marker already covers identity, and repeating it is what made the old
strip invisible. Its form follows what the reach is. The raw SQL console, whose
executor carries no tenant predicate, shows `<.alert kind={:warning}>` beside
the query it runs, stating that SQL there reads across every company and
tenant. The authorization listings, which the platform-operator scope widens to
rows attached to no company, carry a one-line `text-warning-ink` caption with
the registry's `warning` glyph directly above the table, because that widening
is a standing property of the rows rather than an event. The roles list is not
widened, but its per-role Principals counts are, so it carries the same caption
naming the counts rather than the rows. Neither is a gate:
no confirmation, no extra click, and no change to what the surface returns. An
ordinary scope never sees either caution, and a surface whose reach is
filtered to one company carries none. Belimbing does not caution on these
surfaces at all — it answers a non-operator on the console with 403 and marks
its widened decision log with an "All tenants" toggle plus a table caption —
so the caption is the closer adaptation and the console alert is the
deliberate departure, made because a query there is unbounded.

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
Only a success times out, after eight seconds. Every completed write reports
one, whether or not it was confirmed through the shared confirmation dialog;
an info flash informs without confirming a write and is painted on the blue
`info` role, so the two never look alike. Success and info are announced
politely as a `status`; warning and error interrupt as an `alert`. A panel
that cannot reach the page's flash reports through `<.panel_notice>` under
the same rule: a completed write says success and reads as the success flash
at inline strength, a plain statement stays info and reads as the info flash,
and a refusal is an error announced as an alert. The notice renders above the
panel's table, or inside the panel's open dialog, and is dismissed in place.

## Reduce anxiety

Calm software reduces anxiety. Do not manufacture urgency, FOMO, false
scarcity, badge spam, or engagement loops. Trust comes from steady, honest
state and clear recovery paths.

## Write for humans

Use plain, respectful operational language. Write for the person doing the
work, not for enterprise theatre or system internals.

Operator-facing surfaces carry the idea, not its identifier. A catalog row
(`FND-01`), a Design Spec number (`D01`) or a decision code is a working
reference for plans, `DESIGN.md`, comments and test names; a rendered heading,
menu entry or description leads with the statement itself and never with the
code. A code that a link or test depends on stays as the element's `id` and
nothing more.

## Accessibility and resilience

Design for keyboard use, readable contrast, visible focus, semantic structure,
and screen-reader comprehension. Loading, empty, error, disabled, and
permission-denied states are part of the design—not afterthoughts.

The page must remain understandable when JavaScript is unavailable or a LiveView
connection is temporarily interrupted. Preserve meaningful server-rendered
content and communicate reconnection states honestly.
