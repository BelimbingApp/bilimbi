# Base Tiling

Base Tiling owns the tiled workspace at `/workspace`: several Bilimbi pages
side by side in one browser tab, arranged by a Hyprland-style dwindle tree
with keyboard control, drag resizing, monocle, and layouts saved per account.

`Bilimbi.Base.Tiling.Layout` is the pure tree: open, close, resize, move,
swap, flip, directional neighbours, the rectangles every tile and divider
occupies, and the compact URL form (`h.5(/companies,v.6(/users,/audit))`).
`Bilimbi.Base.Tiling.SavedLayouts` keeps an account's saved layouts and its
default in the `ui.workspace.layouts` and `ui.workspace.default` settings at
user scope, through the shared Settings API, so every write is audited.
`Bilimbi.Base.Tiling.Web.WorkspaceLive` is the host page; it holds only the
tree, the focused tile, monocle, and the titles the tiles report.

A tile is a same-origin frame of an existing page at its own URL. The page
runs as its own root LiveView with its own URL state, patches, flash and
capability check, and nothing in any module changes to be shown in a tile.
Base UI renders the framed page chromeless; the Web host marks framed
requests (`BilimbiWeb.FramedRender`) and ships the `Tiling` hook
(`apps/web/assets/js/tiling.js`) with the keyboard bridge into each frame,
the `Ctrl+.` tiling mode, drag resizing and the frame reports. The tile bar
and split handle are shared Base UI components, presented in the Design
Library.

This module depends on Settings and UI. The host page lives here rather than
in Base UI because Settings itself depends on Base UI for its own screens,
so Base UI cannot read saved layouts.

Deferred to later slices: a follow channel between tiles, the master layout,
layouts shared per role or company, Domain-contributed default layouts, and
nested-LiveView tiles.
