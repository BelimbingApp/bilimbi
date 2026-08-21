defmodule Mix.Tasks.Bilimbi.Screenshot do
  @shortdoc "Captures an authenticated screenshot of a route for the visual review lane"

  @moduledoc """
  Reviewer tooling for the #614 visual review lane. Renders an installed screen
  exactly as a signed-in operator sees it and writes a PNG.

      mix bilimbi.screenshot /companies/1
      mix bilimbi.screenshot /dashboard --out tmp/screenshots/dashboard.png
      mix bilimbi.screenshot /employees --viewport 1440x1024 --theme dark

  What it does, end to end:

    1. Refuses outside the `dev` Mix environment.
    2. Builds front-end assets if `priv/static` has none yet.
    3. Serves the endpoint on `--port` (default 4021) so it never collides with a
       long-lived dev server on 4000.
    4. Seeds the platform-operator identity + login through `mix bilimbi.dev.seed`
       and grants that user every capability any installed route declares, so any
       screen is reachable. The dev login is read at run time from the
       `BILIMBI_DEV_LOGIN_EMAIL` / `BILIMBI_DEV_LOGIN_PASSWORD` environment
       variables — never committed or printed (AGENTS.md §16).
    5. Drives the cached Playwright chromium through the real login form and
       captures the route to a git-ignored `tmp/screenshots/` (light theme unless
       `--theme dark`), failing loud on a broken or blank route.

  It is **reviewer tooling, not a CI gate** — nothing here runs in CI. It is safe
  to run repeatedly; the seed and grants are idempotent.

  ## Options

    * `--out FILE`      — output path (default `tmp/screenshots/<route>.png`)
    * `--port N`        — HTTP port to serve on (default 4021)
    * `--viewport WxH`  — viewport in CSS pixels (default 1440x900)
    * `--theme t`       — `light` (default) or `dark`
  """

  use Mix.Task

  @default_port 4021
  @email_env "BILIMBI_DEV_LOGIN_EMAIL"
  @password_env "BILIMBI_DEV_LOGIN_PASSWORD"

  @switches [out: :string, port: :integer, viewport: :string, theme: :string]

  # apps/web/priv/screenshot, resolved at compile time in this checkout.
  @driver_dir Path.expand("../../../priv/screenshot", __DIR__)

  @impl Mix.Task
  def run(argv) do
    {opts, positional} = OptionParser.parse!(argv, strict: @switches)

    route =
      case positional do
        [route | _] -> normalize_route(route)
        [] -> Mix.raise("usage: mix bilimbi.screenshot ROUTE [--out FILE] [--port N] ...")
      end

    ensure_dev!()
    {email, password} = login!()
    ensure_assets!()

    port = opts[:port] || @default_port
    System.put_env("PORT", Integer.to_string(port))
    Application.put_env(:phoenix, :serve_endpoints, true)
    Mix.Task.run("app.start")

    seed_and_grant!(email)
    ensure_node_deps!()

    out = Path.expand(opts[:out] || default_out(route))
    capture!(port, route, out, opts, email, password)

    Mix.shell().info([:green, "screenshot: ", :reset, out])
  end

  # The dev login is a local credential — read it from the environment at run
  # time and never commit or print it (AGENTS.md §16). It must match the login
  # `mix bilimbi.dev.seed` provisions; see priv/screenshot/README.md.
  defp login! do
    email = System.get_env(@email_env)
    password = System.get_env(@password_env)

    if blank?(email) or blank?(password) do
      Mix.raise("""
      Set #{@email_env} and #{@password_env} to your local `mix bilimbi.dev.seed`
      login before capturing. They are read from the environment at run time and
      are never committed (AGENTS.md §16). See apps/web/priv/screenshot/README.md.
      """)
    end

    {email, password}
  end

  defp blank?(value), do: is_nil(value) or value == ""

  # --- environment + assets ---

  defp ensure_dev! do
    unless Mix.env() == :dev do
      Mix.raise("mix bilimbi.screenshot only runs in the dev environment (got #{Mix.env()})")
    end
  end

  defp ensure_assets! do
    if Path.wildcard(Path.join([@driver_dir, "..", "static", "assets", "*.css"])) == [] do
      Mix.shell().info("screenshot: building assets (first run)…")
      Mix.Task.run("assets.setup")
      Mix.Task.run("assets.build")
    end
  end

  # --- seed + grants (public APIs only) ---

  defp seed_and_grant!(email) do
    # `bilimbi.dev.seed` prints the seeded password; run it through the quiet
    # shell so the credential is never printed (AGENTS.md §16).
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)

    try do
      Mix.Task.run("bilimbi.dev.seed")
    after
      Mix.shell(previous_shell)
    end

    alias Bilimbi.Base.Authz
    alias Bilimbi.Base.Tenancy
    alias Bilimbi.Core.Company
    alias Bilimbi.Core.User

    {:ok, company} = Company.platform_operator_company()
    {:ok, scope} = Tenancy.scope(company.tenant_id)
    {:ok, users} = User.list_company_users(scope, company.id)

    user =
      Enum.find(users, &(&1.email == email)) ||
        Mix.raise("dev seed did not produce the login configured in #{@email_env}")

    Enum.each(route_capabilities(), fn capability ->
      {:ok, :stored} =
        Authz.put_principal_capability(scope, company.id, :user, user.id, capability, true)
    end)

    :ok
  end

  # Every distinct capability any installed route declares, harvested from the
  # compiled route manifest — so the operator can reach any screen without a
  # hand-maintained list drifting from the routes.
  defp route_capabilities do
    manifest = Path.join(Mix.Project.build_path(), "bilimbi_routes.exs")

    manifest
    |> Code.eval_file()
    |> elem(0)
    |> Enum.map(&Map.get(&1, :capability))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # --- node driver ---

  defp ensure_node_deps! do
    unless File.dir?(Path.join(@driver_dir, "node_modules")) do
      Mix.shell().info("screenshot: installing Playwright (first run)…")

      {out, status} =
        System.cmd("npm", ["install", "--no-audit", "--no-fund"],
          cd: @driver_dir,
          env: [{"PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD", "1"}],
          stderr_to_stdout: true
        )

      if status != 0 do
        Mix.raise("npm install failed in #{@driver_dir}:\n#{out}")
      end
    end
  end

  defp capture!(port, route, out, opts, email, password) do
    # Credentials go to the driver only via env (never argv/ps), and are not
    # logged by this task.
    env = [
      {"SHOT_BASE_URL", "http://127.0.0.1:#{port}"},
      {"SHOT_ROUTE", route},
      {"SHOT_EMAIL", email},
      {"SHOT_PASSWORD", password},
      {"SHOT_OUT", out},
      {"SHOT_VIEWPORT", opts[:viewport] || "1440x900"},
      {"SHOT_THEME", opts[:theme] || "light"}
    ]

    {output, status} =
      System.cmd("node", ["capture.mjs"], cd: @driver_dir, env: env, stderr_to_stdout: true)

    IO.write(output)

    if status != 0 do
      Mix.raise("screenshot capture failed (exit #{status}) for #{route}")
    end
  end

  # --- helpers ---

  defp normalize_route("/" <> _ = route), do: route
  defp normalize_route(route), do: "/" <> route

  defp default_out(route) do
    slug =
      route
      |> String.trim_leading("/")
      |> String.replace(~r/[^a-zA-Z0-9]+/, "_")
      |> String.trim("_")

    slug = if slug == "", do: "root", else: slug
    Path.join(["tmp", "screenshots", slug <> ".png"])
  end
end
