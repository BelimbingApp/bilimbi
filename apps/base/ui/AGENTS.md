# Base UI

Read the component comment before fighting a default. `DESIGN.md` is the design source. This note is the mistakes, plus the asset rules.

## Component modules

Shared components live in five modules: `lib/ui/components.ex`, and `icon.ex`, `forms.ex`, `lists.ex` and `flex_table.ex` under `lib/ui/components/`. Take them with `use Bilimbi.Base.UI.Components`, not `import`: a plain import brings only what `components.ex` still defines, so `<.icon>`, `<.input>` and `<.table>` are undefined. A new group joins `Components.modules/0` and the `__using__` there, or the Design Library guards never measure it. The moduledoc of `Bilimbi.Base.UI.Components` owns the import order.

## Defaults the component owns

Use `<.secret_input>` for password and encrypted-value forms, not a hand-written password field. Its comment in `lib/ui/components/forms.ex` owns masking, the default eye, the accessible noun, and the stored-value clear action; the owning form decides what a submitted mask or blank means.
The optional stored-value reveal button is separate from the eye. Wire its `stored_reveal` event only after the server checks an explicit grant; `BilimbiWeb.SecretReveal` rechecks, confirms the viewer's password, audits, and sends one timed value. If that audit write cannot land, refuse the reveal and send nothing — see the `:audit_unavailable` path in `BilimbiWeb.SecretReveal` and its LiveView coverage in `apps/base/settings/web_test/settings_secret_reveal_test.exs`.

Use `<.restricted>` for a field the viewer may not see (a `Bilimbi.Base.Authz.Restricted` value in a summary), never a hand-written dash, blank, or "redacted" span, and never an editor around it; in a create or edit form use `<.restricted_field>`, a read-only row that keeps its label and submits nothing, never an omitted input. Pass `roles={value.roles}` so the tooltip names the roles to ask for. Their comments in `lib/ui/components/forms.ex` own the wording, the lock and the tooltip; `apps/base/authz/docs/README.md` "Field-level authorization" owns when a value is withheld.

Use `<.inline_long_text>` for an in-place multi-line fact; its hook owns focus, Escape cancellation, blur commit and the saving wait, while the record owner keeps validation and persistence. Do not rebuild the textarea lifecycle in a LiveView. See its component comment and `DESIGN.md` "Inline editing".

Use `<.tabs>` for sibling views of one page. Its comment owns the narrow-screen strip: one line, horizontal scroll, and edge controls only while a tab is out of view. A hand-rolled flex row of links clips the later labels on a phone.

A table is flat. `table/1` takes no radius, so a rounded table is hand-written markup. See `DESIGN.md` "Table geometry" and the comment on `table/1`.

A caller's `inner_class` padding wins over the card's `p-2`. `inner_padding/1` resolves that before the classes reach the markup; two utilities of equal specificity are decided by stylesheet order, where a caller's `p-0` would lose.

Rendered text carries no catalog identifier. A Design Spec number may be the element's `id` and nothing the person reads. See `DESIGN.md` "Write for humans".

A list a form field opens beneath itself carries `floating-list`, its control `floating-anchor` and the field wrapper `floating-scope`, as `multi_select/1` and `combobox/1` do. Do not give such a list `absolute`: inside `<.modal>` or any box that scrolls or clips it was cut off and grew a scrollbar. The comment above the three utilities in `apps/web/assets/css/app.css` owns the rule, and happy-dom cannot show it, so check a new one in a browser.

`<.modal>` scrolls its body, never the rounded dialog; do not put `overflow-y-auto` or padding on the dialog through `class`. See the comment on `modal/1`.

## Design Library

A specimen calls the real component. Do not fake behaviour to make an example look finished: a simulated 1.2-second wait was removed from the confirmation specimen. Do not mount a second live copy of something the layout already renders: the connection banners. Anchor, state, and catalog rules are `Bilimbi.Base.UI.DesignLibrarySource`. Its guards, `design_library_coverage_test.exs` and `design_library_imitation_test.exs`, run in every `mix test`, and `design_library_rules_test.exs` proves on fixtures that the rules still match. When one fails, fix the specimen or the component, never the guard.

Each area page (`DesignLibraryComponentsLive`, `DesignLibraryGraphicLive`, …) is a thin wrapper over `DesignLibraryLive`. A wrapper that serves an interactive specimen delegates `handle_event/3` too; without it the first event raises `UndefinedFunctionError` and the view crashes.

## Confirmation

An action that cannot be undone uses `<.confirm_dialog>`. A native `data-confirm` is a defect. The caller holds the record and stops rendering the dialog whatever the outcome. See `DESIGN.md` "Confirmation dialogs" and the comment on `confirm_dialog/1`.

## Assets and generators

Colours come from the `@theme` block in `apps/web/assets/css/app.css`. A raw palette class outside that block is a defect, and `.github/scripts/mandates.sh` fails CI on one (`app.css` is the one allowed location):

```bash
grep -rnE '\b(bg|text|border|ring|shadow|divide|accent)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]+' apps/*/lib apps/*/*/lib apps/domains/*/*/lib apps/extensions/*/*/lib
```

Do not use `@apply`. Sidebar pin and tile buttons are `<.icon_button chrome={:nav}>`; that chrome is the `nav-icon-button` utility in `apps/web/assets/css/app.css`, and the comment on `icon_button/1` says why the utility list is not repeated on the button. The shell reads `Bilimbi.Base.UI.Nav.rendered_tree/1`, which `Nav.on_mount/4` fills and refreshes only when capabilities or pins change. Do not call `Nav.tree/1` from a render. Sidebar pins are `current_scope.pins`, rendered as `data-pins` on `#app-shell`. Do not load pins in the layout or fetch them on shell mount; the hook reads the attribute and requests `/api/pins` only after a toggle that did not return the list. Do not add an external script or stylesheet URL. Do not write a raw `<script>` in HEEx. A colocated hook follows `apps/web/mix/README.md`: `:type={Phoenix.LiveView.ColocatedHook}`, a dot-prefixed local name, the owner's descriptor namespace, and no `runtime`. An external hook lives in `apps/web/assets/js/`, has a DOM id, and `phx-update="ignore"` when it owns its DOM. Rebind the socket `push_event/3` returns.

Copy to the clipboard through the `ClipboardCopy` hook (`apps/web/assets/js/clipboard_copy.js`), not a click handler that shows "Copied" on its own. The hook reports whether the browser accepted the write, and the server shows the outcome, so a refused copy is never announced as done. The Graphic page's icon catalogue is the caller.

`phx.gen.live`, `phx.gen.html`, and `phx.gen.schema` use `Bilimbi.Base.UI.Components`. `phx.gen.auth` emits daisyUI classes; convert them to semantic roles in the same change. Base UI components are hand-written Tailwind, and no third-party component library, daisyUI included, becomes the design system. Name an action through `Bilimbi.Base.UI.IconRegistry`. Logout stays `hero-arrow-right-on-rectangle`.

`phx-disable-with` belongs on a text control only; it replaces the label, so it wipes an icon button. A wait the server knows about is `<.button busy>` or `<.icon_button busy>`. An async action rejects duplicate work; see the comment on `busy_rest/2`.

Keep the `source(none)` and `@source` lines in `app.css`; the comment above them says why.

The page-loading bar is the vendored canvas `apps/web/assets/vendor/topbar.js`, not CSS. The global reduced-motion rule cannot slow it; the marked `prefers-reduced-motion` check in that file is what keeps the bar still. A new canvas or timer animation has to make the same check.

## Component activity

Authenticated LiveComponents receive `current_scope` and use the shared
`:live_component` setup. `Bilimbi.Base.UI.ComponentActivity` forwards their
events to the authenticated host for session activity; component handlers do
not select session IDs or write session metadata.

## Hook tests

A hook in `apps/web/assets/js` is tested beside it in `apps/web/assets/test/<hook>.test.mjs`, with Node's own test runner and happy-dom. `mix precommit` runs them through `mix assets.test`; `npm test` in `apps/web/assets` runs them alone. Mount the hook with `test/support/hook.mjs` on the markup its component renders, carrying the JS commands the server really renders, and assert what a person meets: attributes, focus, events pushed. Compare focus by id with `focused()`, because a failed assertion on two DOM nodes never finishes printing.

happy-dom has no top layer, makes nothing inert, and does not blur an element that becomes hidden. Check those in a browser. A new hook test goes in Node, not in an ExUnit test that shells out to `node`. Shell out only for what this runner cannot give: another host locale, the shipped LiveView bundle, or markup the server renders in the same test.

## Shell panels

The notification bell is the shell's: `Layouts.app/1` renders the `shell.notifications` panel on every authenticated page, and `Bilimbi.Core.User.Web.NotificationSubscription` keeps it live. Do not paste the bell into a page's `<:topbar_actions>`, subscribe a page to notifications, or `send_update` a shell panel by a literal id; a page that pasted the bell is why 49 pages had none while every one of them was subscribed. A new shell-wide panel is an `embed: "shell.<name>"` entry rendered with `<.discovered_panel optional>` and the id from `DiscoveredPanels.shell_id/1`; the moduledoc of `Bilimbi.Base.UI.DiscoveredPanels` owns the contract.

## Tiled workspace

A page shown inside a workspace tile renders chromeless through the `framed` branch of `Layouts.app/1`; the flag comes from `BilimbiWeb.FramedRender` through the LiveView session, never from a page. Do not add a tile special case to a page: if a page needs to know it is in a tile beyond that branch, that is the signal to design a tile contract, not a special case. A tile has no bar: its chrome is `<.tile_controls>`, a grip and a two-entry menu floating over its top right corner, and the divider is `<.split_handle>`. Do not add an operation to that menu; a new tile operation is a key of the tiling mode, added to `tiling.js` and the key table in `apps/base/tiling/docs/README.md` together, and the comment on `tile_controls/1` says why. The tree, the host page and its hook are `apps/base/tiling` and `apps/web/assets/js/tiling.js`. See `DESIGN.md` "Tiled workspace".

A tile has one vertical scrollbar. Do not give a page or a component a height of its own (`h-screen`, a `max-h` scroll box around a list) to get a sticky heading or a pinned pager: build the list from `<.page>`, `<.card>`, `<.table>` or `<.flex_table>`, and `<.pagination>`, and the "list fill" rules in `apps/web/assets/css/app.css` do it inside a tile for the shapes named there. A scroll box needs a positioned ancestor inside it or around it, as the comment on the framed `main` in `layouts.ex` explains: an `sr-only` label under an unpositioned scroll box is laid out against the document and gave every tile a second scrollbar.

The one tile contract so far is the follow channel, `Bilimbi.Base.UI.Workspace`. A list row that opens a record is `<.record_link workspace={@workspace} kind="core/company" record_id={id} navigate={...}>`, and a record page calls `Workspace.announce/2` once it has loaded the record; both are inert outside a workspace. Pass `@workspace` to the component; do not branch a page template on it, and do not decide from the followed kinds at render time: rows are streamed and re-render only when re-streamed, so the component decides when the row is clicked. `kind` is the record's owning module id, which for `/users/:id` is `core/user`, not the list's module. The comment on `record_link/1` and the moduledoc of `Workspace` own the rest.

Opening a page in a tile from anywhere is a link to `/workspace` with `open=<the page>`, which the workspace resolves and replaces (URL form in `apps/base/tiling/docs/README.md`); the sidebar's control is `nav_tile/1` in `layouts.ex`, retargeted by `AppShell.retargetTileLink`. Do not encode a workspace tree on the client or add a second "open in a tile" control that builds its own address. The tile count has no cap, and a page does not check its own tile size.

## Lists

Parse an operational list's URL state with `Bilimbi.Base.UI.ListState` and coerce a param with `Bilimbi.Base.UI.Params`. A private `to_int`, `positive_integer`, `nilify`, or `state_from_params` is the copy those replaced. The moduledocs own the contract; `<.filter_toolbar>` and `<.pagination>` in `lib/ui/components/lists.ex` still own the framing.

## Flexible tables

A table whose columns a person adds, removes or reorders is
`<.flex_table>`, hosted by a list page through
`Bilimbi.Base.Grid.Web.PageColumns`. It is presentation only: it never
touches a catalog or a query, and its one event carries an `op`. Bars and
bands are painted from `data-bar`, `data-band` and `data-scale` (the CSP
refuses inline style; the `FlexTable` hook writes the bar width). It is
one real table at every zoom: do not add a canvas, and do not offer a row
height that looks like its neighbour (`Bilimbi.Base.UI.FlexTable` owns the
steps). A compact row is as short as 18px, so a `<.badge>` in one gives up
its vertical padding through the `data-badge` rule in
`apps/web/assets/css/app.css` and a row action takes 16px; do not hand-shrink
either in a page. Its chips, add box, zoom and reset live in table customization,
the bar the lip on the table's top-left edge opens; do not put a toolbar
or an icon group back above the table or in its heading row. A zoom
control carries `data-zoom-op` and no `phx-click`: LiveView drops a click
on a control still waiting for its last reply, which is how the first
density toggle came to look stuck, so the hook pushes each press. A page
that draws a second line or an avatar in a `<:col>` leaves it out when the
mode is `:compact`. In a `p-0` card the flexible table is `framed={false}`,
as `table/1` is `framed={false}` there, so the card is the one frame;
`class="p-2"` drew a second frame 8px inside the card's. The notch then
rises out of the card, and the card's headroom for it is the `data-unframed`
rule in `apps/web/assets/css/app.css`: do not add a margin or padding for
it at a call site. See the component comment in
`lib/ui/components/flex_table.ex` and `Bilimbi.Base.UI.FlexTable`.

## Summaries

A dashboard card of labelled values is `<.stat_strip>`; a hand-written card with the same title-and-cells anatomy is what it replaced. A feed of entries is not a stat strip: the section uses `<.card>`, `<.section_heading>` and `<.empty_state>`, and the entry rows stay local, commented as such. An icon-only link is `<.icon_button navigate>`, which carries the accessible name a bare `<.link>` around an icon lacks.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
