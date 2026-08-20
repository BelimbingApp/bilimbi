# Base Principal Directory

The seam Base screens use to name the people behind grants, sessions and
assignments, without Base depending on Core.

Specified in
[`docs/architecture/decisions/0011-principal-directory-seam.md`](../../../../docs/architecture/decisions/0011-principal-directory-seam.md).

- **Consumers name their candidates.** Select the distinct `{kind, id}` pairs
  your already-filtered query references, before pagination, and pass those.
  Never ask for a tenant.
- **Order in the database.** Feed the returned order to `array_position/2` so
  ordering happens before `offset`/`limit`.
- **Identity is `{principal_type, principal_id}`**, never an id alone.
- **Failure is visible.** `{:error, :too_many_candidates}` and
  `{:error, :name_search_unavailable}`; an unresolvable principal is absent and
  keeps its row with the durable type and id.
