# Belimbing schema fixture

`schema.sql` is a schema-only `pg_dump` of a database that upstream
Belimbing's own Laravel migrations created, at the commit named in its
header and returned by `Bilimbi.Core.Compatibility.compatibility_source/0`.

It exists because a Bilimbi baseline proving itself against a database
built from Bilimbi baselines proves nothing about adoption. Three defects
(a unique constraint dropped as an index, indexes created twice, two upstream
columns the contracts had never seen) each passed every test until
`mix bilimbi.migrate` met a database Laravel had made. The test
`BelimbingSchemaAdoptionE2ETest` loads this file into a throwaway database
and runs `bilimbi.schema.verify`, `bilimbi.schema.adopt`, `bilimbi.migrate`
and `bilimbi.schema.verify` again from the umbrella root, as an operator does.

Rules:

- The source is the public `BelimbingApp/belimbing` repository, never a
  customer database and never a fork that carries customer modules. The
  file holds structure only: no rows, no owners, no names.
- Regenerate it with `regenerate.sh <commit>` when the compatibility source
  advances, in the same change that moves `compatibility_source/0`; the
  test fails while the two disagree.
- Do not edit the file by hand. A contract that disagrees with it is fixed
  in the contract or the baseline, with the upstream migration named.
