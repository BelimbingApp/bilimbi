Code.require_file(Path.expand("../mix/local_config.exs", __DIR__))

try do
  case System.argv() do
    ["https", root] ->
      options = root |> Bilimbi.LocalConfig.load() |> Bilimbi.LocalConfig.https_options()
      IO.puts(options.host)
      IO.puts(options.port)

    ["save-https", root, host, port] ->
      Bilimbi.LocalConfig.save_https!(root, host, String.to_integer(port))

    _ ->
      raise ArgumentError, "Usage: local-config.exs https ROOT | save-https ROOT HOST PORT"
  end
rescue
  error in [ArgumentError, File.Error] ->
    IO.puts(:stderr, Exception.message(error))
    System.halt(1)
end
