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
names are preserved when locally edited. Postcode refreshes replace one
country's upstream rows transactionally, then rematerialize operator
corrections before the transaction commits.

Callers use the public facade for country, administrative-division, and
postcode lookups. Table schemas and query details remain private to the module.

## Administration indexes

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
25-row defaults, page sizes clamped to 25/50/100/300, allow-listed sorting,
and deterministic ties. Postcode country totals are a separately sortable,
unpaginated summary bounded by the imported-country set. Exact
`lookup_postcode/2` remains the address-workflow locality lookup.

Address forms use two additional bounded, schema-free reference-data reads:

```elixir
Geonames.search_postcodes(country_iso, prefix)
Geonames.search_city_names(country_iso, query, admin1_code: full_or_raw_code)
```

Postcode search returns at most ten distinct ascending values. City search
returns names from at most 15 population-ordered candidate rows before exact
deduplication, and accepts either raw GeoNames Admin1 values or the module's
full `CC.value` identities. Both APIs treat caller text literally, including
SQL wildcard and escape characters, and return an empty list for an invalid
country identity. These are global reference-data reads and deliberately take
no tenancy scope.

## Operator postcode corrections

The Postcodes index supports creation, inline place-name correction, and full
record editing under `admin.geonames.update`. Every persistence event evaluates
the actor's current grants again; the capability shown when the LiveView
mounted is presentation state, not an authorization decision.

`geonames_postcodes` remains the Belimbing-compatible source and lookup table.
Bilimbi does not add provenance columns to it. Instead, the Bilimbi-only
`geonames_postcode_overrides` sidecar stores the desired operator record, its
original upstream field snapshot when one exists, and an optimistic revision.
The public API materializes the desired row into the compatible table so
existing Address callers continue to use the same lookups.

During a country refresh, the importer selects overrides by both original and
desired country. Inside the same transaction it replaces upstream rows,
matches an original snapshot when possible, removes any prior materialization,
and applies the operator record exactly once. An upstream row that changes so
it no longer matches the snapshot remains visible alongside the local record;
Bilimbi does not silently hide new upstream facts. Operator-created rows have
no source snapshot and are reinserted after every refresh of their country.

Writes validate live country and Admin1 identities, required and bounded text,
paired latitude/longitude ranges, and GeoNames accuracy values 1 through 6.
Updates require the revision returned by `page_postcodes/1`; stale revisions
return `{:error, :stale}` without changing either the sidecar or compatible
table.
