defmodule Bilimbi.Base.Authz.ArchivedCompanyTest do
  @moduledoc """
  Every Authz write that lands in a company asks the company directory
  whether that company may be written. The test double reports company 13
  as archived: in scope for every read, refused by every write with
  `:company_archived`, including a write that reaches the company through
  the record it changes.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.PrincipalCapability
  alias Bilimbi.Base.Authz.PrincipalRole
  alias Bilimbi.Base.Authz.Role
  alias Bilimbi.Base.Authz.TestCompanyDirectory
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures

  import Bilimbi.Base.Authz.TestFixtures

  @archived TestCompanyDirectory.archived_company_id()
  @capability "admin.test.record.view"

  setup do
    create_authz_tables!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    %{scope: TenancyFixtures.scope()}
  end

  test "the directory keeps the company visible and refuses to write it", %{scope: scope} do
    assert TestCompanyDirectory.company_in_scope?(scope, @archived)
    assert {:error, :company_archived} = Authz.company_writable(scope, @archived)
    assert :ok = Authz.company_writable(scope, 10)
    assert {:error, :company_not_found} = Authz.company_writable(scope, 99)
  end

  test "roles cannot be created in, moved into, changed in or deleted from it", %{scope: scope} do
    assert {:error, :company_archived} =
             Authz.create_role(scope, @archived, %{name: "Frozen", code: "frozen"})

    {:ok, role} = Authz.create_role(scope, 10, %{name: "Clerks", code: "clerks"})

    assert {:error, :company_archived} =
             Authz.update_role(scope, role.id, %{company_id: @archived})

    # A role already owned by the archived company: the write reaches the
    # company through the role.
    frozen = Repo.insert!(Role.custom_changeset(@archived, %{name: "Frozen", code: "frozen"}))

    assert {:ok, %{role: %{company_id: @archived}}} = Authz.get_role(scope, frozen.id)

    assert {:error, :company_archived} = Authz.update_role(scope, frozen.id, %{name: "Thawed"})
    assert {:error, :company_archived} = Authz.replace_role_capabilities(scope, frozen.id, [])
    assert {:error, :company_archived} = Authz.delete_role(scope, frozen.id)
    assert {:ok, _role} = Authz.get_role(scope, frozen.id)
  end

  test "assignments and direct grants in it are neither added nor removed", %{scope: scope} do
    {:ok, role} = Authz.create_role(scope, 10, %{name: "Clerks", code: "clerks"})

    assert {:error, :company_archived} =
             Authz.assign_role(scope, @archived, :user, 7, role.id)

    assert {:error, :company_archived} =
             Authz.put_principal_capability(scope, @archived, :user, 7, @capability, true)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, [assignment]} =
      Repo.insert_all(
        PrincipalRole,
        [
          %{
            company_id: @archived,
            principal_type: "user",
            principal_id: 7,
            role_id: role.id,
            created_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    {1, [grant]} =
      Repo.insert_all(
        PrincipalCapability,
        [
          %{
            company_id: @archived,
            principal_type: "user",
            principal_id: 7,
            capability_key: @capability,
            is_allowed: true,
            created_at: now,
            updated_at: now
          }
        ],
        returning: [:id]
      )

    assert {:error, :company_archived} = Authz.unassign_role(scope, role.id, assignment.id)
    assert {:error, :company_archived} = Authz.remove_principal_capability(scope, grant.id)
    assert Repo.exists?(PrincipalRole)
    assert Repo.exists?(PrincipalCapability)
  end
end
