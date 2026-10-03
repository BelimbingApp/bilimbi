# Base Settings work

Use `Settings.get_many/2` for multiple values and `Settings.resolve_many/2`
when override and source metadata are needed. Both use one uncached query
snapshot. Single-row reads outside transactions use `Settings.Cache`; write
through `Settings.put/3` and `Settings.delete/2` so `Repo.after_commit/1`
invalidates the matching cache entry after the outer transaction commits.
See `docs/README.md` for the TTL and multi-node invalidation contract.
