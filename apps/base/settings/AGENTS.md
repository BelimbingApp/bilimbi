# Base Settings work

Use `Settings.get_many/2` for a form or read that needs multiple setting
values; it fetches requested key and scope pairs together. All ordinary row
reads go through `Settings.Cache`; write through `Settings.put/3` and
`Settings.delete/2` so the matching cache entry is invalidated. See
`docs/README.md` for the TTL and multi-node invalidation contract.
