# Base UI

Read the component comment before fighting a default. `DESIGN.md` is the design source. This note is the mistakes, plus the asset rules that used to sit only in the root guide.

## Defaults the component owns

A table is flat. `table/1` takes no radius, so a rounded table is hand-written markup. See `DESIGN.md` "Table geometry" and the comment on `table/1`.

A caller's `inner_class` padding wins over the card's `p-2`. `inner_padding/1` resolves that before the classes reach the markup; two utilities of equal specificity are decided by stylesheet order, where a caller's `p-0` would lose.

Rendered text carries no catalog identifier. A Design Spec number may be the element's `id` and nothing the person reads. See `DESIGN.md` "Write for humans".

## Design Library

A specimen calls the real component. Do not fake behaviour to make an example look finished: a simulated 1.2-second wait was removed from the confirmation specimen. Do not mount a second live copy of something the layout already renders: the connection banners. Anchor, state, and catalog rules are `Bilimbi.Base.UI.DesignLibrarySource`. Its two guards, `design_library_coverage_test.exs` and `design_library_imitation_test.exs`, run in every `mix test`. When one fails, fix the specimen or the component, never the guard.

Each area page (`DesignLibraryComponentsLive`, `DesignLibraryGraphicLive`, …) is a thin wrapper over `DesignLibraryLive`. A wrapper that serves an interactive specimen delegates `handle_event/3` too; without it the first event raises `UndefinedFunctionError` and the view crashes.

## Confirmation

An action that cannot be undone uses `<.confirm_dialog>`. A native `data-confirm` is a defect. The caller holds the record and stops rendering the dialog whatever the outcome. See `DESIGN.md` "Confirmation dialogs" and the comment on `confirm_dialog/1`.

## Assets and generators

Colours come from the `@theme` block in `apps/web/assets/css/app.css`. A raw palette class outside that block is a defect:

```bash
grep -rnE '\b(bg|text|border|ring|shadow|divide|accent)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]+' apps/*/lib
```

Do not use `@apply`. Do not add an external script or stylesheet URL. Do not write a raw `<script>` in HEEx. A colocated hook uses `:type={Phoenix.LiveView.ColocatedHook}` and a name that starts with `.`. An external hook lives in `assets/js/`, has a DOM id, and `phx-update="ignore"` when it owns its DOM. Rebind the socket `push_event/3` returns.

Copy to the clipboard through the `ClipboardCopy` hook (`apps/web/assets/js/clipboard_copy.js`), not a click handler that shows "Copied" on its own. The hook reports whether the browser accepted the write, and the server shows the outcome, so a refused copy is never announced as done. The Graphic page's icon catalogue is the caller.

`phx.gen.live`, `phx.gen.html`, and `phx.gen.schema` use `Bilimbi.Base.UI.Components`. `phx.gen.auth` emits daisyUI classes; convert them to semantic roles in the same change. Base UI components are hand-written Tailwind, and no third-party component library, daisyUI included, becomes the design system. Name an action through `Bilimbi.Base.UI.IconRegistry`. Logout stays `hero-arrow-right-on-rectangle`.

`phx-disable-with` belongs on a text control only; it replaces the label, so it wipes an icon button. A wait the server knows about is `<.button busy>` or `<.icon_button busy>`. An async action rejects duplicate work; see the comment on `busy_rest/2`.

Keep the `source(none)` and `@source` lines in `app.css`; the comment above them says why.

The page-loading bar is the vendored canvas `apps/web/assets/vendor/topbar.js`, not CSS. The global reduced-motion rule cannot slow it; the marked `prefers-reduced-motion` check in that file is what keeps the bar still. A new canvas or timer animation has to make the same check.

## Hook tests

A hook in `apps/web/assets/js` is tested beside it in `apps/web/assets/test/<hook>.test.mjs`, with Node's own test runner and happy-dom. `mix precommit` runs them through `mix assets.test`; `npm test` in `apps/web/assets` runs them alone. Mount the hook with `test/support/hook.mjs` on the markup its component renders, carrying the JS commands the server really renders, and assert what a person meets: attributes, focus, events pushed. Compare focus by id with `focused()`, because a failed assertion on two DOM nodes never finishes printing.

happy-dom has no top layer, makes nothing inert, and does not blur an element that becomes hidden. Check those in a browser. A new hook test goes in Node, not in an ExUnit test that shells out to `node`. Shell out only for what this runner cannot give: another host locale, the shipped LiveView bundle, or markup the server renders in the same test.

## Lists

An operational list keeps its page, search, filters, sort and page size in URL state. See `DESIGN.md` "Pagination controls".

Those filters are `<.filter_toolbar>` and that pager is `<.pagination>`. A local form or Previous/Next pair is the pair those two replaced. The comments on `filter_toolbar/1` and `pagination/1` own the framing.

## Summaries

A dashboard card of labelled values is `<.stat_strip>`; a hand-written card with the same title-and-cells anatomy is what it replaced. A feed of entries is not a stat strip and keeps its own markup, commented as such. An icon-only link is `<.icon_button navigate>`, which carries the accessible name a bare `<.link>` around an icon lacks.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
