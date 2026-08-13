# Core Geonames

`core/geonames` owns Bilimbi's compatible geographic reference-data schema and
lookup API. Its physical boundary is this directory and its public namespace is
`Bilimbi.Core.Geonames`.

The compatibility baseline creates the four canonical Belimbing tables:
countries, first-level administrative divisions, postcodes, and cities. Fresh
installation intentionally creates no reference rows; imports remain an
explicit operational action:

```bash
mix bilimbi.geonames.import
mix bilimbi.geonames.import --postcodes MY,SG
```

Countries, administrative divisions, and cities import by default. Postcodes
are opt-in because their size varies substantially by country. Downloads use
ETag-aware caching with a seven-day modification-time fallback. Set a durable
cache with `--cache-dir`; the default is the operating system temporary
directory.

Imports stream and batch rows rather than loading global datasets into memory.
Each dataset import is atomic: a database failure in any batch rolls the whole
dataset back and surfaces as `{:error, {:import, dataset, {:database, _}}}`,
and a payload with no valid rows is rejected with
`{:error, {:import, dataset, :no_valid_rows}}`. A failed import restores the
previously known-good download cache. Country and administrative-division
names are preserved when locally edited, while postcode refreshes replace one
country's rows transactionally.

Callers use the public facade for country, administrative-division, and
postcode lookups. Table schemas and query details remain private to the module.

## Read-only indexes

The module also owns the bounded read models used by its three administration
indexes. They are global reference-data queries, not tenant-scoped operations:

```elixir
Geonames.page_countries(query)
Geonames.page_admin1(query)
Geonames.admin1_filter_countries()
Geonames.page_postcodes(query)
Geonames.list_postcode_country_summaries(query)
```

The page queries return `Bilimbi.Core.Geonames.Page` with schema-free entries,
20-row defaults, page sizes clamped to 20/50/100/300, allow-listed sorting,
and deterministic ties. Postcode country totals are a separately sortable,
unpaginated summary bounded by the imported-country set. Exact
`lookup_postcode/2` remains the address-workflow lookup; prefix postcode and
city combobox searches are intentionally outside this module UI slice.
