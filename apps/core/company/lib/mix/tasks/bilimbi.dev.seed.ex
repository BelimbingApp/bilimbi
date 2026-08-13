defmodule Mix.Tasks.Bilimbi.Dev.Seed do
  @shortdoc "Seeds the local development platform identity"

  @moduledoc """
  Seeds the minimal identity required to use Bilimbi in local development.

      mix bilimbi.dev.seed

  The seed provisions an explicitly marked platform-operator tenant and its
  primary company through the public Company API. It is safe to run more than
  once: an existing platform identity is resolved rather than duplicated or
  overwritten.

  This task refuses to run outside the `dev` Mix environment.
  """

  use Mix.Task

  alias Bilimbi.Core.Company

  @tenant_name "Bilimbi local development"
  @company_attributes %{
    name: "Bilimbi Development",
    code: "bilimbi_dev",
    legal_name: "Bilimbi Development",
    jurisdiction: "MY",
    metadata: %{"purpose" => "local_development"}
  }

  @impl Mix.Task
  def run(arguments) do
    reject_arguments!(arguments)
    ensure_development!()
    Mix.Task.run("app.start")

    case Company.provision_platform_operator(@tenant_name, @company_attributes) do
      {:ok, result} ->
        Mix.shell().info(
          "Development seed ready: tenant #{result.tenant.id} (#{result.tenant_status}), " <>
            "company #{result.company.id} (#{result.company_status})."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise("development seed failed: #{inspect(changeset.errors)}")
    end
  end

  defp reject_arguments!([]), do: :ok

  defp reject_arguments!(_arguments) do
    Mix.raise("bilimbi.dev.seed accepts no arguments")
  end

  defp ensure_development! do
    if Mix.env() != :dev do
      Mix.raise("bilimbi.dev.seed can only run in the dev Mix environment")
    end
  end
end
