defmodule Mix.Tasks.Bilimbi.Authz.Reconcile do
  @moduledoc "Explicitly reconciles configured Authz system roles and their capability mappings."

  use Mix.Task

  alias Bilimbi.Base.Authz

  @shortdoc "Reconciles configured Authz system roles"

  @impl true
  def run(args) do
    if args != [], do: Mix.raise("unexpected arguments: #{Enum.join(args, " ")}")

    Mix.Task.run("app.start")

    case Authz.reconcile_system_roles() do
      {:ok, summary} ->
        Mix.shell().info(
          "Reconciled #{summary.roles} system roles with #{summary.capabilities} mapping changes."
        )

      {:error, reason} ->
        Mix.raise("Authz system-role reconciliation failed: #{inspect(reason)}")
    end
  end
end
