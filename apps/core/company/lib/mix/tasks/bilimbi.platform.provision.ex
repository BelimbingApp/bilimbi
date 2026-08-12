defmodule Mix.Tasks.Bilimbi.Platform.Provision do
  @shortdoc "Provisions the explicit platform operator and its primary company"

  @moduledoc """
  Provisions the explicit platform-operator tenant and its primary company.

      mix bilimbi.platform.provision --tenant-name "Platform operator" --company-name "Example Operations" --company-code "example_operations"

  `--company-name` and `--company-code` are required. `--tenant-name` defaults
  to the company name. Re-running the command resolves the existing explicit
  relationship and does not create a second operator or company.
  """

  use Mix.Task

  alias Bilimbi.Core.Company

  @switches [tenant_name: :string, company_name: :string, company_code: :string]

  @impl Mix.Task
  def run(arguments) do
    {options, positional, invalid} = OptionParser.parse(arguments, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise("invalid arguments; run mix help bilimbi.platform.provision")
    end

    company_name = required_option!(options, :company_name)
    company_code = required_option!(options, :company_code)
    tenant_name = normalized_option(options, :tenant_name) || company_name

    Mix.Task.run("app.start")

    case Company.provision_platform_operator(tenant_name, %{
           name: company_name,
           code: company_code
         }) do
      {:ok, result} ->
        Mix.shell().info(
          "Platform operator ready: tenant #{result.tenant.id} (#{result.tenant_status}), " <>
            "company #{result.company.id} (#{result.company_status})."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise("platform provisioning failed: #{inspect(changeset.errors)}")
    end
  end

  defp required_option!(options, key) do
    normalized_option(options, key) ||
      Mix.raise("--#{key |> Atom.to_string() |> String.replace("_", "-")} is required")
  end

  defp normalized_option(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          normalized -> normalized
        end

      _other ->
        nil
    end
  end
end
