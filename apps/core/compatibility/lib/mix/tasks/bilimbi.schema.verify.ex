defmodule Mix.Tasks.Bilimbi.Schema.Verify do
  @moduledoc """
  Verifies the live Base Tenancy and Core Company tables against Bilimbi's
  pinned Belimbing compatibility contract.

      mix bilimbi.schema.verify
      mix bilimbi.schema.verify --prefix custom_schema

  The task is read-only and exits with an error when owned structure or
  bootstrap invariants drift.
  """

  use Mix.Task

  @shortdoc "Verifies the pinned Belimbing-compatible Base and Company schema"
  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, remaining} = OptionParser.parse!(args, strict: [prefix: :string])

    if remaining != [] do
      Mix.raise("unexpected arguments: #{Enum.join(remaining, " ")}")
    end

    case Bilimbi.Core.Compatibility.verify(Bilimbi.Base.Repo, opts) do
      :ok ->
        Mix.shell().info("Bilimbi compatibility schema verified.")

      {:error, errors} ->
        details = Enum.map_join(errors, "\n", &"  - #{&1}")
        Mix.raise("Bilimbi compatibility schema drift detected:\n#{details}")
    end
  end
end
