# Checkout-local development configuration

This directory belongs to **this checkout**. This README is versioned;
`config.json` and generated HTTPS state are Git-ignored.
Development Mix commands read `config.json`; test and production environments
do not. Other checkouts have their own `.local/config.json` files. Shared URL
registrations live in `/etc/caddy/bilimbi/*.caddy`.

## Edit `config.json`

Stop this checkout's server before changing its database or HTTPS settings.
Use ordinary JSON with two-space indentation, for example:

```json
{
  "database": {
    "name": "bilimbi_sbg_dev"
  },
  "https": {
    "host": "sbg.bilimbi.localhost",
    "port": 4001
  }
}
```

Both sections and every field are optional. Unknown fields, malformed JSON and
invalid values stop startup with a diagnostic. JSON has no comments; keep
checkout-specific operator notes in another file in `.local/`.

| Field | Meaning | Default |
| --- | --- | --- |
| `database.name` | Database for this checkout; use a separate name for independent branches | `bilimbi_dev` |
| `database.host` | PostgreSQL hostname | `localhost` |
| `database.port` | PostgreSQL port, an integer from 1 to 65535 | `5433` |
| `database.username` | PostgreSQL role | `bilimbi` |
| `database.password` | Local development connection password | Repository development default |
| `https.host` | Lowercase hostname ending in `.localhost` | Automatically allocated |
| `https.port` | Loopback HTTP backend port, an integer from 1024 to 65535 | Automatically allocated |
| `https.root` | Automatically saved checkout ownership marker | This checkout's absolute path |

The browser URL always uses HTTPS on port **443**. `https.port` is the internal
Phoenix port behind Caddy. Startup remembers its allocation and preserves the
`database` section when updating HTTPS settings. Leave `https.root` unchanged.
If copying settings to a different checkout, remove the `https` section so the
new checkout can allocate its own address.

## Environment overrides

1. `DATABASE_URL`, when set, overrides the entire database connection.
2. Otherwise `PGDATABASE`, `PGHOST`, `PGPORT`, `PGUSER` and `PGPASSWORD` override
   their corresponding database fields.
3. `BILIMBI_DEV_HOST` and `PORT` override the corresponding HTTPS fields.
4. Saved JSON values override the repository defaults.

Variables provided by Mise have the same precedence as shell variables. Remove
old database overrides from `.mise.local.toml` when moving those settings into
`config.json`. To deliberately use the saved database selection despite an
existing shell override, run:

```bash
env -u DATABASE_URL -u PGDATABASE mix bilimbi.server
```

## Start the checkout

Run these commands from the repository root. Create the database once when
choosing a new name, then start normally:

```bash
mix ecto.create -r Bilimbi.Base.Repo
mix bilimbi.server
```

Startup configures local Caddy HTTPS, validates and runs the checkout's own
migrations, and prints the URL. An already running instance is reported.
Separate databases keep different branches' migration ledgers independent;
do not remove ledger entries to make an older checkout use a newer database.
Stop Phoenix with Ctrl+C; the shared Caddy service remains running.

## Files in this directory

- `config.json`: saved database and HTTPS settings. Generated files have mode
  `0600`; preserve that mode when editing connection credentials.
- `https/`: local leaf certificates, private keys and startup locks. Caddy gets
  protected copies of the leaf files. The CA private key stays in mkcert's own
  CA directory.
- `README.md`: these versioned instructions, included in every checkout.

Old `https/instance.json` settings migrate into `config.json` automatically.
Discovery responses such as `resource.json` are checked without saving a file.
Disposable logs and test captures belong under `tmp/`.

More detail is in the [`development guide`](../docs/development.md).
