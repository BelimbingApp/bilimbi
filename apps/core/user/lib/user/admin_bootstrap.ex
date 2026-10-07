defmodule Bilimbi.Core.User.AdminBootstrap do
  @moduledoc false

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy
  alias Bilimbi.Core.Company
  alias Bilimbi.Core.User
  alias Bilimbi.Core.User.BootstrapReceipt
  alias Bilimbi.Core.User.Schema
  alias Ecto.Adapters.SQL

  @identity_keys [:tenant_name, :company_name, :company_code, :admin_email]
  @required @identity_keys ++ [:admin_name]

  @spec run(map()) :: {:ok, :created | :already_completed} | {:error, atom()}
  def run(attributes) when is_map(attributes) do
    if Enum.all?(@required, &nonempty?(Map.get(attributes, &1))) do
      Repo.transact(fn ->
        # This fresh-installation invariant belongs to User. The table lock
        # serializes bootstrap AND ordinary account inserts before the global
        # emptiness proof; an advisory lock alone would not protect that proof.
        SQL.query!(Repo, "LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE", [])

        status =
          case Repo.get(BootstrapReceipt, 1) do
            nil -> provision!(attributes)
            receipt -> completed!(receipt, attributes)
          end

        {:ok, status}
      end)
    else
      {:error, :invalid_bootstrap_attributes}
    end
  end

  defp completed!(receipt, attributes) do
    identity = Map.from_struct(receipt)

    if Enum.all?(@identity_keys, &(Map.fetch!(identity, &1) == Map.fetch!(attributes, &1))) do
      :already_completed
    else
      Repo.rollback(:bootstrap_identity_conflict)
    end
  end

  defp provision!(attributes) do
    # No lowest-id or oldest-account inference, and no promotion of an
    # adopted account. Even a company-less account means this is not fresh.
    if Repo.exists?(Schema), do: Repo.rollback(:existing_users)
    if Tenancy.platform_operator(), do: Repo.rollback(:existing_platform_operator)
    unless nonempty?(Map.get(attributes, :password)), do: Repo.rollback(:password_required)

    result =
      unwrap!(
        Company.provision_platform_operator(
          attributes.tenant_name,
          Map.merge(Map.take(attributes, [:legal_name, :jurisdiction, :metadata]), %{
            name: attributes.company_name,
            code: attributes.company_code
          })
        )
      )

    # Another trusted provisioning command can create an operator without
    # inserting users. Refuse its identity if it won the provisioning race.
    if result.tenant_status != :created or result.company_status != :created do
      Repo.rollback(:existing_platform_operator)
    end

    scope = unwrap!(Tenancy.scope(result.tenant.id))

    role =
      Enum.find(
        Authz.list_roles(scope),
        &(&1.is_system and &1.code == "core_admin" and &1.grant_all)
      ) ||
        Repo.rollback(:system_roles_missing)

    user =
      unwrap!(
        User.register_user(scope, result.company.id, %{
          name: attributes.admin_name,
          email: attributes.admin_email,
          password: attributes.password
        })
      )

    unwrap!(Authz.assign_role(scope, result.company.id, :user, user.id, role.id))

    %BootstrapReceipt{}
    |> Ecto.Changeset.change(
      Map.merge(Map.take(attributes, @identity_keys), %{
        id: 1,
        user_id: user.id,
        company_id: result.company.id,
        tenant_id: result.tenant.id,
        completed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
    )
    |> Repo.insert!()

    unwrap!(
      Audit.record_action(scope, %{
        actor_type: "console",
        actor_id: 0,
        company_id: result.company.id,
        event: "user.bootstrap.completed",
        is_retained: true,
        occurred_at: NaiveDateTime.utc_now(),
        payload: %{user_id: user.id, email: user.email, role: role.code}
      })
    )

    :created
  end

  # Changesets may carry plaintext passwords in their changes. Keep them out
  # of release output and seed ledgers; validation failures have one safe code.
  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, %Ecto.Changeset{}}), do: Repo.rollback(:invalid_bootstrap_attributes)
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)
  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""
end
