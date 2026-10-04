# Base Menu

**Stable module ID:** `base/menu` · **Layer:** Base · required
**Canonical source:** Belimbing `app/Base/Menu` and every module's `Config/menu.php`

Owns the navigation tree. No tables, no I/O.

## How an item gets into the menu

Its **owning module** contributes it, exactly as Belimbing declares items in
each module's `Config/menu.php`:

```elixir
@impl true
def contributions do
  %{menu: [%{id: "admin.employee", label: "Employees", parent: "admin",
             route: "/employees", capability: "admin.employee.list", order: 30}]}
end
```

`id`, `label`, `icon`, `route`, `parent` and `capability` are Belimbing's item
shape — `capability` is our name for its `permission`.

## Public API

| Function | Purpose |
|---|---|
| `items/0` | Every validated item, ordered |
| `tree/0` | Full tree, unfiltered — diagnostics and tests |
| `visible_tree/1` | What an actor may see; **render this** |
| `fetch_item/1` | Look up one item |

`visible_tree/1` takes a function deciding one capability, so Menu does not
depend on Authz. Pass a closure over `Bilimbi.Base.Authz.can/4`.

## Behaviour taken from Belimbing

- **Index everything, then validate parents.** Contribution order never decides
  whether an item resolves, so a child may name a parent owned by another
  module (`MenuRegistry.php:67-75`).
- **A missing parent drops that item with a warning**, it does not raise. One
  module shipping a dangling parent must not take down navigation.
- **A container with no visible child is hidden**, so a section never renders
  as an empty heading. This is also what keeps unported Domain roots out of the
  menu until their Domains are installed.

Duplicate ids and circular parents **do** raise — contributor defects with no
safe interpretation, where silently keeping one item would make navigation
depend on load order.

## Hiding is not authorization

`visible_tree/1` is presentation. The route must enforce the same capability at
mount. Belimbing works the same way: the menu filters on `permission` and the
route carries `authz:<capability>` middleware.

## Combined pages

Keep a single capability as a string. A combined page may declare the same
any-of requirement on its menu leaf and in its owning module's route file:

```elixir
# In the :menu contribution
%{id: "self.standing", label: "My standing", route: "/standing",
  capability: {:any_of, ["self.summary.view", "self.performance.view"]}}

# In priv/web_routes.exs
%{path: "/standing", live: Example.Web.StandingLive, session: :auth,
  capability: {:any_of, ["self.summary.view", "self.performance.view"]}}
```

Declare each key through the module's Authz contribution as usual. At least
one live allow opens the route; holders of neither are refused. This applies
to LiveView mounts, navigation to another guarded route, and controller routes.
Menu visibility and workspace tile previews use the account's effective allows.
The route gate is [Route gate](../../authz/docs/README.md#route-gate).
Operator-only restrictions still apply.

The list must be non-empty, with distinct, non-blank strings. Menu contribution
validation rejects malformed declarations at boot; route discovery rejects
them before compilation. Bare lists, nested policies and all-of policies are
unsupported. Embedded panels keep their existing single-capability contract.
`nil` retains its existing meaning: no capability restriction at that boundary.

An any-of guard permits entry only. Each section, read and mutation inside the
page must enforce its own capability through its owning API. A performance
allow must not reveal or permit changes to a separately protected summary.
`Bilimbi.Base.Menu.Capability` owns evaluation and diagnostic formatting.
