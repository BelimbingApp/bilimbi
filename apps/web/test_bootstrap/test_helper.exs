# Elixir 1.20.3's Mix.Tasks.Test uses Enum.any?/2 to load test helpers, so a
# warning in one helper stops it from loading the rest. Load every discovered
# bridge here before test compilation. Diagnostics still reach Mix's normal
# warnings-as-errors handling; no warning is suppressed. Revisit on Elixir upgrades.
# Load the host helper first to completion: module bridges require it themselves.
Code.require_file(Path.expand("../test/test_helper.exs", __DIR__))

"../../.."
|> Path.expand(__DIR__)
|> Bilimbi.Base.ModuleRegistry.MixDiscovery.web_test_paths()
|> Enum.each(&Code.require_file(Path.join(&1, "test_helper.exs")))
