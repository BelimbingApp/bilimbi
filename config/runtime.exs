import Config

if System.get_env("PHX_SERVER") do
  config :web, BilimbiWeb.Endpoint, server: true
end

if belimbing_app_key = System.get_env("BELIMBING_APP_KEY") do
  config :bilimbi_base_settings, :belimbing_app_key, belimbing_app_key
end

if geonames_cache_dir = System.get_env("GEONAMES_CACHE_DIR") do
  config :bilimbi_core_geonames, :cache_dir, geonames_cache_dir
end

if trusted_proxies = System.get_env("TRUSTED_PROXIES") do
  config :web, :trusted_proxies, BilimbiWeb.ForwardedFor.parse!(trusted_proxies)
end

env_port = System.get_env("PORT")

http_port =
  if is_nil(env_port) and config_env() == :dev do
    # Another dev server may already hold 4000; take the next free port.
    Enum.find(4000..4019, 4000, fn port ->
      case :gen_tcp.listen(port, ip: {127, 0, 0, 1}) do
        {:ok, socket} -> :gen_tcp.close(socket) == :ok
        {:error, _} -> false
      end
    end)
  else
    String.to_integer(env_port || "4000")
  end

if config_env() == :dev and http_port != 4000 do
  IO.puts("Port 4000 is in use; starting on http://127.0.0.1:#{http_port}")
end

config :web, BilimbiWeb.Endpoint, http: [port: http_port]

if config_env() == :dev do
  config :web, BilimbiWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"apps/web/priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"apps/web/priv/gettext/.*\.po$"E,
        ~r"apps/web/lib/bilimbi_web/router\.ex$"E,
        ~r"apps/web/lib/bilimbi_web/(controllers|live|components)/.*\.(ex|heex)$"E,
        ~r"apps/[^/]+/[^/]+/lib/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  config :web, BilimbiWeb.Mailer, BilimbiWeb.MailerConfig.production_config!()
  config :web, :mailer_sender, BilimbiWeb.MailerConfig.sender!()

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :bilimbi_base_database, Bilimbi.Base.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with `mix phx.gen.secret`.
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :web, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :web, BilimbiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base

  # Base Tenancy derives its own keys from this secret with distinct salts:
  # one seals the actor on every tenant scope, one signs queued jobs that act
  # for a user. Rotating SECRET_KEY_BASE invalidates those queued jobs.
  config :bilimbi_base_tenancy, :actor_secret, secret_key_base
end
