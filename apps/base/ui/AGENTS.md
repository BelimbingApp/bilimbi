# Base UI

Read the component comment before fighting a default. `DESIGN.md` is the design source. This note is the mistakes, plus the asset rules that used to sit only in the root guide.

## Defaults the component owns

A table is flat. `table/1` takes no radius, so a rounded table is hand-written markup. See `DESIGN.md` "Table geometry" and the comment on `table/1`.

A caller's `inner_class` padding wins over the card's `p-2`. `inner_padding/1` resolves that before the classes reach the markup; two utilities of equal specificity are decided by stylesheet order, where a caller's `p-0` would lose.

Rendered text carries no catalog identifier. A Design Spec number may be the element's `id` and nothing the person reads. See `DESIGN.md` "Write for humans".

## Design Library

A specimen calls the real component. Do not fake behaviour to make an example look finished: a simulated 1.2-second wait was removed from the confirmation specimen. Do not mount a second live copy of something the layout already renders: the connection banners. Anchor, state, and catalog rules are `Bilimbi.Base.UI.DesignLibrarySource`.

## Confirmation

An action that cannot be undone uses `<.confirm_dialog>`. A native `data-confirm` is a defect. The caller holds the record and stops rendering the dialog whatever the outcome. See `DESIGN.md` "Confirmation dialogs" and the comment on `confirm_dialog/1`.

## Assets and generators

Colours come from the `@theme` block in `apps/web/assets/css/app.css`. A raw palette class outside that block is a defect:

```bash
grep -rnE '\b(bg|text|border|ring|shadow|divide|accent)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]+' apps/*/lib
```

Do not use `@apply`. Do not add an external script or stylesheet URL. Do not write a raw `<script>` in HEEx. A colocated hook uses `:type={Phoenix.LiveView.ColocatedHook}` and a name that starts with `.`. An external hook lives in `assets/js/`, has a DOM id, and `phx-update="ignore"` when it owns its DOM. Rebind the socket `push_event/3` returns.

`phx.gen.live`, `phx.gen.html`, and `phx.gen.schema` use `Bilimbi.Base.UI.Components`. `phx.gen.auth` emits daisyUI classes; convert them to semantic roles in the same change. Base UI components are hand-written Tailwind, and no third-party component library, daisyUI included, becomes the design system. Name an action through `Bilimbi.Base.UI.IconRegistry`. Logout stays `hero-arrow-right-on-rectangle`.

`phx-disable-with` belongs on a text control only; it replaces the label, so it wipes an icon button. A wait the server knows about is `<.button busy>` or `<.icon_button busy>`. An async action rejects duplicate work; see the comment on `busy_rest/2`.

Keep the `source(none)` and `@source` lines in `app.css`; the comment above them says why.

## Hook tests

A hook in `apps/web/assets/js` is tested beside it in `apps/web/assets/test/<hook>.test.mjs`, with Node's own test runner and happy-dom. `mix precommit` runs them through `mix assets.test`; `npm test` in `apps/web/assets` runs them alone. Mount the hook with `test/support/hook.mjs` on the markup its component renders, carrying the JS commands the server really renders, and assert what a person meets: attributes, focus, events pushed. Compare focus by id with `focused()`, because a failed assertion on two DOM nodes never finishes printing.

happy-dom has no top layer, makes nothing inert, and does not blur an element that becomes hidden. Check those in a browser. A new hook test goes in Node, not in an ExUnit test that shells out to `node`; the ones left there run Node under a host locale or against the LiveView bundle.

## Lists

An operational list keeps its page, search, filters, sort and page size in URL state. See `DESIGN.md` "Pagination controls".

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
