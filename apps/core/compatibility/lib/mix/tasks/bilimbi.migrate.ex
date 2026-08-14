defmodule Mix.Tasks.Bilimbi.Migrate do
  @moduledoc "Runs every installed module migration through Bilimbi's shared Repo and ledger."

  use Mix.Task

  @shortdoc "Runs installed Bilimbi module migrations"
  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    run(args, Bilimbi.Base.Repo)
  end

  @doc false
  def run(args, repo) do
    {parsed, remaining} =
      OptionParser.parse!(args,
        strict: [prefix: :string, quiet: :boolean]
      )

    if remaining != [] do
      Mix.raise("unexpected arguments: #{Enum.join(remaining, " ")}")
    end

    opts =
      parsed
      |> Keyword.delete(:quiet)
      |> then(fn opts ->
        if parsed[:quiet], do: Keyword.put(opts, :log, false), else: opts
      end)

    Bilimbi.Core.Compatibility.migrate(repo, opts)
  end
end
