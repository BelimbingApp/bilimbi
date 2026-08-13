import Config

if System.get_env("PHX_SERVER") do
  config :web, BilimbiWeb.Endpoint, server: true
end

if belimbing_app_key = System.get_env("BELIMBING_APP_KEY") do
  config :bilimbi_base_settings, :belimbing_app_key, belimbing_app_key
end

config :web, BilimbiWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :web, BilimbiWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"apps/web/priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"apps/web/priv/gettext/.*\.po$"E,
        ~r"apps/web/lib/bilimbi_web/router\.ex$"E,
        ~r"apps/web/lib/bilimbi_web/(controllers|live|components)/.*\.(ex|heex)$"E,
        ~r"apps/[^/]+/[^/]+/lib/.*\.ex$"E
      ]
    ]
end

if config_env() == :prod do
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
end
