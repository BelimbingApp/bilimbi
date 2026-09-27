# Base Tiling

Base Tiling owns the tiled workspace at `/workspace`: several Bilimbi pages
side by side in one browser tab, arranged by a Hyprland-style dwindle tree
with keyboard control, drag resizing, drag-to-swap, monocle, and layouts
saved per account.

The usual entry is the sidebar's "Open in a tile" control beside each row's
pin. It links to `/workspace?t=<the page the browser is on>&inplace=1&open=<the
clicked page>`; from the workspace itself, it is the address already open
plus `open`, and the link is a patch, so the tiles on screen keep their frames. The workspace
reads `t`, halves the tile with the most room with the page in `open`, and
replaces the address with the resulting tree, so a refresh or a shared link
restores the screen. Tiling in place and the `/workspace` picker are one
feature with one URL form. A workspace entered from a page this way carries
`inplace=1` in every address it writes, except a saved layout's, so even
after a refresh it leaves for that page's own address when closed down to
one tile; one opened from
the picker or a saved layout stays a workspace with one tile. On a narrow
screen the control opens the page normally.

There is no cap on the number of tiles; the operator decides. Each tile is a
live page: its own LiveView process, socket and database checkouts on the
server, and its own document in the browser. A wall of twenty tiles costs
what twenty tabs cost, and a page that polls does so once per tile. The
operator decides tile sizes, so a small tile keeps showing its page; the
tile menu's monocle fills the workspace with it.

`Bilimbi.Base.Tiling.Layout` is the pure tree: open, close, resize, move,
swap, flip, directional neighbours, the rectangles every tile and divider
occupies, and the compact URL form (`h.5(/companies,v.6(/users,/audit))`).
`Bilimbi.Base.Tiling.SavedLayouts` keeps an account's saved layouts and its
default in the `ui.workspace.layouts` and `ui.workspace.default` settings at
user scope, through the shared Settings API, so every write is audited.
`Bilimbi.Base.Tiling.SharedLayouts` keeps published layouts in the
`ui.workspace.shared_layouts` setting at company scope. An empty role list
shares with the company; role codes limit who sees a layout. Publishing and
administration require `ui.workspace.publish`. A viewer may open or copy a
shared layout, while every tile still applies that viewer's route access. An
account without a company sees no shared layouts and keeps its own.
`Bilimbi.Base.Tiling.Web.WorkspaceLive` is the host page; it holds only the
tree, the focused tile, monocle, and the titles the tiles report. The
sidebar control is `nav_tile/1` in Base UI's `Layouts`, and `AppShell`
(`apps/web/assets/js/app_shell.js`) retargets its click from the address the
browser is on.

A tile is a same-origin frame of an existing page at its own URL. The page
runs as its own root LiveView with its own URL state, patches, flash and
capability check, and nothing in any module changes to be shown in a tile.
Base UI renders the framed page chromeless; the Web host marks framed
requests (`BilimbiWeb.FramedRender`) and ships the `Tiling` hook
(`apps/web/assets/js/tiling.js`) with the keyboard bridge into each frame,
the `Ctrl+.` tiling mode, drag resizing and the frame reports. The tile bar
and split handle are shared Base UI components, presented in the Design
Library.

Tiles talk through the follow channel, `Bilimbi.Base.UI.Workspace`: one
PubSub topic per workspace, named by the account and a token the host
derives from its LiveView id and puts in every frame's URL as `?ws=`. The
Web host copies the token of a framed request into the signed LiveView
session, and the `Workspace.on_mount/4` hook on every discovered
`live_session` joins the page to the topic. A tile showing one record can
follow selections: the tree keeps that page's route pattern
(`/companies/42>/companies/:id` in the URL form), and when a page announces
a record of the module that owns the pattern, the host fills the id in and
the hook sends the frame there. A page opts in with `<.record_link>` on its
rows and `Workspace.announce/2` at mount; the Company, Employee and User
lists and record pages do.

This module depends on Authz, Settings and UI. The host page lives here
rather than in Base UI because Settings itself depends on Base UI for its own
screens, so Base UI cannot read saved layouts.

Deferred to later slices: the master layout, Domain-contributed default
layouts, and nested-LiveView tiles.
