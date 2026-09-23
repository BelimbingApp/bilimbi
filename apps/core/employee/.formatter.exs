[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test,web_test}/**/*.{heex,ex,exs}",
    "priv/repo/migrations/*.exs",
    "priv/web_routes.exs"
  ]
]
