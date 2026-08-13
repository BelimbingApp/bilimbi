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
