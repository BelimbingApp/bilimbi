defmodule Bilimbi.Core.Company.WritableCompany do
  @moduledoc false

  # The one "may this company be written?" check. An archived company is
  # read-only for good: its own facts and every record it owns (departments,
  # relationships, external accesses, addresses, employees, users and their
  # roles and grants, settings scoped to it) refuse to change, while every
  # read keeps working. This module is where that refusal lives; the public
  # faces are `Bilimbi.Core.Company.require_writable_company/2` (existence
  # for a write) and `lock_writable_company/2` (the row lock a sibling
  # workflow takes before its own locks), and `Bilimbi.Core.Company.archived?/1`
  # for a page deciding what to offer. Base modules reach the same answer
  # through the Authz company directory's `company_writable/2`.
  #
  # Soft deletion (`deleted_at`) stays a separate fact: a soft-deleted
  # company is not found at all, as in every live-company read. Only a live
  # row whose status is `archived` is `{:error, :company_archived}`. Do not
  # add a second status comparison in a sibling: call this.

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company.Schema

  @archived "archived"

  @type error :: :not_found | :company_archived

  @spec archived_status() :: String.t()
  def archived_status, do: @archived

  @doc """
  The live company row when it may be written, or why it may not be.

  `lock: true` takes the row `FOR UPDATE` first, so the status judged is the
  one the caller's transaction will see until it commits.
  """
  @spec fetch(Scope.t(), term(), keyword()) :: {:ok, Schema.t()} | {:error, error()}
  def fetch(scope, company_id, opts \\ [])

  def fetch(%Scope{} = scope, company_id, opts)
      when is_integer(company_id) and company_id > 0 do
    query =
      from(company in Tenancy.scope_query(Schema, scope),
        where: company.id == ^company_id and is_nil(company.deleted_at)
      )

    query = if Keyword.get(opts, :lock, false), do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> {:error, :not_found}
      %Schema{status: @archived} -> {:error, :company_archived}
      %Schema{} = company -> {:ok, company}
    end
  end

  def fetch(%Scope{}, _company_id, _opts), do: {:error, :not_found}

  @doc "The aggregates' spelling: a missing parent company is `:company_not_found`."
  @spec fetch_parent(Scope.t(), term()) ::
          {:ok, Schema.t()} | {:error, :company_not_found | :company_archived}
  def fetch_parent(%Scope{} = scope, company_id) do
    case fetch(scope, company_id) do
      {:error, :not_found} -> {:error, :company_not_found}
      other -> other
    end
  end
end
