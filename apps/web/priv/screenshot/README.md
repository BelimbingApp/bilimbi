# Screenshot harness (`mix bilimbi.screenshot`)

Reviewer tooling for the [#614](https://github.com/BelimbingApp/bilimbi/issues/614)
visual review lane. It renders an installed screen exactly as a signed-in
operator sees it and writes a PNG, so a reviewer can compare against the
dashboard / `<.table>` exemplars, the Belimbing screen at the pin, and
AGENTS.md §12.

**It is reviewer tooling, not a CI gate.** Nothing here runs in CI.

## Setup

The harness logs in as your local dev login, read from the environment at run
time (a local credential — never committed or printed, AGENTS.md §16). Export
these to the login `mix bilimbi.dev.seed` provisions (its values live in that
task's source, `apps/core/user/lib/mix/tasks/bilimbi.dev.seed.ex`):

```bash
export BILIMBI_DEV_LOGIN_EMAIL=…      # the dev.seed login email
export BILIMBI_DEV_LOGIN_PASSWORD=…   # the dev.seed login password
```

## Usage

```bash
# from the umbrella root or apps/web, in the dev environment
mix bilimbi.screenshot /dashboard
mix bilimbi.screenshot /companies/1 --out tmp/screenshots/company.png
mix bilimbi.screenshot /employees --viewport 1440x1024 --theme dark
```

Options: `--out FILE`, `--port N` (default 4021), `--viewport WxH` (default
1440x900), `--theme light|dark`. Output defaults to `tmp/screenshots/<route>.png`
(git-ignored).

## What it does

1. Refuses outside the `dev` Mix environment.
2. Builds front-end assets on first run if `priv/static` has none.
3. Serves the endpoint on `--port` (default 4021, so it never collides with a
   long-lived dev server on 4000).
4. Seeds the platform-operator identity + login via `mix bilimbi.dev.seed` (run
   quietly so its credential is not printed) and grants that user every
   capability any installed route declares — harvested from the compiled route
   manifest, so no hand-maintained list drifts — so any screen is reachable. The
   login itself comes from the environment (see **Setup**).
5. Drives the cached Playwright chromium (`capture.mjs`) through the **real**
   login form (which also smoke-tests auth), navigates to the route, grows the
   viewport to the app shell's content height (the shell is `h-screen` and
   scrolls `#app-content`, so Playwright's `fullPage` alone clips below the
   fold), and writes the PNG. It **fails loud** on a broken, redirected, or
   blank route — the #409 discipline applies to tooling too.

## Caveats

- **Assets are built only if missing, not if stale.** After changing CSS/JS,
  run `mix assets.build` yourself so the capture reflects your changes rather
  than a previously built bundle.
- **The capture operator is a dev-superuser by construction** — it is granted
  every capability any route declares (the SQL console included) so any screen
  is reachable. That is correct for dev-only reviewer tooling; do not reuse this
  grant-everything pattern outside `dev`.

## Dependencies

`capture.mjs` uses [Playwright](https://playwright.dev). The task runs
`npm install` here on first use; a chromium browser already in the local
Playwright cache is reused (no download). `node_modules/` is git-ignored.
