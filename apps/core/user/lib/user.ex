defmodule Bilimbi.Core.User do
  @moduledoc """
  Public API for user accounts and their company/employee affiliation.

  Every operation runs under a `Bilimbi.Base.Tenancy.Scope`, so the tenant is
  proven once at the edge. Ecto schemas and the stored credential stay private
  to this deep module.

  Tenancy here is *derived*, not stored. `users` has no `tenant_id` column and
  no soft delete; a user reaches a tenant only through its nullable
  `company_id`. Belimbing's own list
  (`app/Core/User/Livewire/Users/Index.php:110-111`) left-joins `companies` and
  filters `companies.tenant_id`, so a user with no company is invisible to
  every tenant-scoped read. Single-company reads go through
  `Company.get_company/2`; the tenant-wide list goes through
  `Company.list_tenant_company_ids/1` so this module never queries `companies`.

  Soft-deleted companies: Belimbing's raw join still returns those users.
  Bilimbi matches that visibility (BLB-S1-010 option a) via company ids that
  include soft-deleted rows. Live-only company presentation remains
  `Company.list_companies/1`.

  This module stores credentials and never creates them. `create_user/3` takes
  an already-hashed `:password_hash` and rejects anything that is not
  crypt-format. Authentication, registration, password reset, and the hashing
  dependency belong to S2.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Scope
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.Employee
  alias Bilimbi.Core.User.Schema
  alias Bilimbi.Core.User.Summary
  alias Ecto.Changeset

  @type lookup_error :: :company_not_found | :user_not_found

  @doc """
  Lists the users affiliated with one company inside the scope's tenant.

  Ordered by id. A user whose `company_id` is nil belongs to no company and so
  appears in no company list, matching Belimbing.
  """
  @spec list_company_users(Scope.t(), pos_integer()) ::
          {:ok, [Summary.t()]} | {:error, :company_not_found}
  def list_company_users(%Scope{} = scope, company_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)) do
      users =
        from(user in Schema,
          where: user.company_id == ^company_id,
          order_by: user.id
        )
        |> Repo.all()
        |> Enum.map(&Summary.from_schema/1)

      {:ok, users}
    end
  end

  @doc """
  Lists every user visible to the scope's tenant, ordered by id.

  Visibility matches Belimbing's tenant-wide list: affiliation is through any
  company owned by the tenant, including soft-deleted companies. Users with a
  null `company_id` never appear. Company membership is resolved only through
  `Company.list_tenant_company_ids/1`.
  """
  @spec list_users(Scope.t()) :: {:ok, [Summary.t()]}
  def list_users(%Scope{} = scope) do
    {:ok, company_ids} = Company.list_tenant_company_ids(scope)

    users =
      case company_ids do
        [] ->
          []

        ids ->
          from(user in Schema,
            where: user.company_id in ^ids,
            order_by: user.id
          )
          |> Repo.all()
          |> Enum.map(&Summary.from_schema/1)
      end

    {:ok, users}
  end

  @spec get_user(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, Summary.t()} | {:error, lookup_error()}
  def get_user(%Scope{} = scope, company_id, user_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      {:ok, Summary.from_schema(user)}
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  @doc """
  Creates a user affiliated with a company in the scope's tenant.

  `attributes` must carry `:password_hash` holding an already-hashed
  credential. See the module doc for why this module refuses to hash.
  """
  @spec create_user(Scope.t(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, :company_not_found | Changeset.t()}
  def create_user(%Scope{} = scope, company_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)) do
      company_id
      |> Schema.creation_changeset(attributes)
      |> validate_employee(scope, company_id)
      |> persist_insert()
    end
  end

  @spec update_user(Scope.t(), pos_integer(), pos_integer(), map()) ::
          {:ok, Summary.t()} | {:error, lookup_error() | Changeset.t()}
  def update_user(%Scope{} = scope, company_id, user_id, attributes) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      user
      |> Schema.update_changeset(attributes)
      |> validate_employee(scope, company_id)
      |> persist_update()
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  @spec delete_user(Scope.t(), pos_integer(), pos_integer()) :: :ok | {:error, lookup_error()}
  def delete_user(%Scope{} = scope, company_id, user_id) do
    with {:ok, _company} <- normalize_company(Company.get_company(scope, company_id)),
         %Schema{} = user <- user_schema(company_id, user_id) do
      {:ok, _} = Repo.delete(user)
      :ok
    else
      {:error, :company_not_found} = error -> error
      nil -> {:error, :user_not_found}
    end
  end

  @doc """
  The durable polymorphic identity Laravel persists for a user.

  Stored in `notifications.notifiable_type` and, once Authz lands,
  `base_authz_principal_roles.principal_type` companions. It is data, not an
  Elixir module reference: renaming this module must not change the string.
  """
  @spec notifiable_identity() :: String.t()
  def notifiable_identity, do: "App\\Core\\User\\Models\\User"

  # An employee affiliation must belong to the same company as the user.
  # Resolved through Core Employee's public API, never by querying `employees`:
  # that table belongs to another deep module, and `users.employee_id` being a
  # foreign key to it does not grant this module read access to its schema.
  defp validate_employee(%Changeset{valid?: false} = changeset, _scope, _company_id),
    do: changeset

  defp validate_employee(changeset, scope, company_id) do
    case Changeset.get_field(changeset, :employee_id) do
      nil ->
        changeset

      employee_id ->
        case Employee.get_employee(scope, company_id, employee_id) do
          {:ok, _employee} ->
            changeset

          {:error, _reason} ->
            Changeset.add_error(changeset, :employee_id, "does not belong to the company")
        end
    end
  end

  defp user_schema(company_id, user_id) do
    Repo.get_by(Schema, id: user_id, company_id: company_id)
  end

  defp persist_insert(%Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_insert(changeset) do
    case Repo.insert(changeset) do
      {:ok, user} -> {:ok, Summary.from_schema(user)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp persist_update(%Changeset{valid?: false} = changeset), do: {:error, changeset}

  defp persist_update(changeset) do
    case Repo.update(changeset) do
      {:ok, user} -> {:ok, Summary.from_schema(user)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp normalize_company({:ok, company}), do: {:ok, company}
  defp normalize_company({:error, :not_found}), do: {:error, :company_not_found}
end
