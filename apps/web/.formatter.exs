[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{heex,ex,exs}",
    "{lib,test,mix,test_bootstrap}/**/*.{heex,ex,exs}",
    "priv/**/*.{ex,exs}"
  ]
]
