defmodule Bilimbi.Base.Tenancy.SystemPrincipals do
  @moduledoc """
  The named system identities installed modules declare for their jobs.

  A scheduled import is work nobody signed in for, so it must not borrow a
  person's account. It runs as a named system principal instead, such as
  `coating.line_import`: an identity that is never a user, holds no authority by
  default, and can be granted only the capabilities its module declared
  (ADR 0017).

  A module declares its principals under the `:system_principals`
  contribution key:

      system_principals: [
        %{
          name: "coating.line_import",
          description: "Imports coating line production records on a schedule.",
          capabilities: ["factory.material.import"]
        }
      ]

  Names are validated from the composition graph when the contribution
  snapshot is built, so a duplicate or malformed name stops boot. A name no
  installed module declares is refused everywhere: a job cannot run as it,
  and Base Authz grants it nothing.

  Declaring a principal grants nothing. An administrator grants each
  declared capability explicitly, per company, through Base Authz.
  """

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  @type principal :: %{
          name: String.t(),
          description: String.t(),
          capabilities: [String.t()],
          module_id: String.t(),
          otp_app: atom()
        }

  @doc "Every declared principal, ordered by name."
  @spec list() :: [principal()]
  def list, do: declared() |> Map.values() |> Enum.sort_by(& &1.name)

  @doc "The declared principal named `name`."
  @spec fetch(term()) :: {:ok, principal()} | {:error, :undeclared_system_principal}
  def fetch(name) when is_binary(name) do
    case Map.fetch(declared(), name) do
      {:ok, principal} -> {:ok, principal}
      :error -> {:error, :undeclared_system_principal}
    end
  end

  def fetch(_name), do: {:error, :undeclared_system_principal}

  @doc "Whether an installed module declares `name`."
  @spec declared?(term()) :: boolean()
  def declared?(name), do: match?({:ok, _principal}, fetch(name))

  @doc """
  Whether `module` belongs to the module that declared `name`.

  A job runs as a principal only when its worker is code of the declaring
  module, so one module cannot run its work as another module's identity.
  """
  @spec declared_by?(term(), module()) :: boolean()
  def declared_by?(name, module) when is_atom(module) do
    case fetch(name) do
      {:ok, %{otp_app: otp_app}} -> module in (Application.spec(otp_app, :modules) || [])
      {:error, _reason} -> false
    end
  end

  defp declared, do: ContributionRegistry.consumer!(:system_principals) || %{}
end
