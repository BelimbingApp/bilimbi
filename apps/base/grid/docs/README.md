# Base Grid

Base Grid owns flexible columns on list pages: the catalog every module
declares its tables into, the paths a person walks through it to pick
columns without writing a join, the one statement that answers them for
the rows a list already shows, and what each account last arranged on
each list.

It has no page of its own. A table is explored on the list that already
owns its rows, its search, its filters and its pagination.

## The model

A module puts a table in the catalog through its `:grid` contribution
(ADR 0019): the table's `fields`, its `links` to other tables, the
`capability` that reads it, and a `Bilimbi.Base.Grid.Source` whose
`query/1` returns the rows a scope may see, with the owner's own tenant,
soft-delete and company filters applied. The grid wraps every source in a
subquery, so every hop of a path carries its owner's boundary and the grid
never adds a tenant predicate of its own. A link is `:one` (a foreign key
to the target's key, or an edge query that yields one row per parent) or
`:many` (the reverse, or a polymorphic attachment table). A module that
depends on another may declare a link that starts at the other's table,
because the module that owns the edge is the one that knows it.

`Bilimbi.Base.Grid.Catalog.for_scope/1` reads the installed snapshot once
and keeps the tables whose capability the actor holds. Every later call
takes that catalog, so there is no spelling of a path that reaches a table
the account may not read.

A field may carry a `capability` of its own, the key the owning module's
`Bilimbi.Base.Authz.FieldPolicy` names for that column (Core Company's
`tax_id` and `email`). The catalog leaves such a field out for an account
that lacks the key, so the column the record page withholds cannot be
added, suggested, rolled up or kept in a view here either. A table's key,
label and time fields, and the fields a link joins on, cannot carry one:
every reader of the table needs them.

A source's query is built only for a real scope, never at boot: the
snapshot validates declarations without calling `query/1`, and the catalog
learns which key of the query each field is read from the first time a
scope may read the table, then keeps it. So a table bounded by another
module's facts asks that module's public API while building its query (the
users source asks Company for the tenant's company ids) and does not
compose the other module's query into its own, and the application still
boots on a database with no tables.

A column is a spec (`Bilimbi.Base.Grid.Column`): `name`, `company.name`,
`company.parent.name` through one-links; `employees:count`,
`lines.qty:sum`, `tags.name:list`, `lines.sku:latest` through a many-link,
which rolls the reached rows up into one cell. A path holds at most one
many-link, so the root row count never changes whatever is added.
`Bilimbi.Base.Grid.Query` builds one PostgreSQL statement: a LEFT JOIN
per one-link prefix, one grouped subquery per many-link carrying every
aggregate over it, positional bindings and select keys so no atom is ever
made from a typed string. `Bilimbi.Base.Grid.attach/5` runs it for the
rows a page already lists, by key; `expand/4` lists the rows a rollup
collapsed; `stats/3` reads the range of the numeric columns over every
root row, which is what a bar or a band scales to, and returns the
planner's cost estimate for that one whole-table statement.

## The surfaces

`Bilimbi.Base.UI.Components.FlexTable.flex_table/1` is the component; it
is presentation only and pushes one event with an `op`. It is one real
table whose zoom is the height of a row: `Bilimbi.Base.UI.FlexTable` owns
the heights offered, short ones drawn compact (tighter rows that never
wrap) and tall ones normal. A lip on the table's top-left edge opens table
customization, the bar inline above the table that holds the column
chips, their lenses, the add-a-column box, the zoom with its two named
heights and the reset. `Bilimbi.Base.Grid.Lens` prepares a cell for every
lens at once: text, its position on the column's range, the band that
position falls in, a trend's series and a change since a date.

`Bilimbi.Base.Grid.Web.PageColumns` is the host a list page uses: the page
keeps its own query and declares the columns it draws itself as built-ins,
and `PageColumns` adds the walked columns for exactly the listed rows. The
users and companies lists use it. `Bilimbi.Base.Grid.View` is what a
person arranged (columns, lenses, zoom, the comparison date); its module
doc lists the URL keys.

`Bilimbi.Base.Grid.PageViews` keeps that arrangement per account and per
page in the account's `ui.grid.page_columns` setting, written on every
change and read afresh whenever the address names none. A list opens the
way its reader left it; an address that carries `cols`, `lens`, `z` or
`since` wins, so a shared link shows what its sender saw and changes
nobody's memory until the reader arranges something. A removed column of
the page's own is offered again by the add-a-column box, and the reset op
returns the page to its own columns and rows and forgets what was kept.

Lenses are `value`, `bar`, `band`, and, for a count or sum over a dated
many-link, `trend` (the aggregate per calendar month over the last twelve,
a sparkline) and `delta` (the aggregate as of a date, through a FILTER in
the same grouped subquery). The date lives in the view and has a control
in table customization while a column wears the lens.

A walked column does not sort: the page owns the order of its rows.

## Deliberate limits

- **No grid page.** Flexible columns belong on the list that owns the
  rows, with its search, filters and pagination. A page over every catalog
  table would be a second, weaker way into the same records.
- **No named or shared views.** An account's arrangement is remembered,
  not saved under a name; the address is how one is shared.
- **One table at every zoom.** Compact rows are a real table like normal
  ones, so links, sorting and rollups work in both. There is no canvas
  mode, and the zoom offers only heights that draw a different table.
- **No grouping or pivot.** The page's own sort and filters order the
  rows; the catalog only adds columns to them.

## What remains

- Sorting and filtering by a walked column: the page's own query sorts and
  filters, so a walked column is read-only context.
- In-cell editing.
- Base Authz tables (roles, grants) in the catalog.
- More list pages: employees, addresses and the reference lists declare
  their tables in the catalog but do not host the flexible table yet.
