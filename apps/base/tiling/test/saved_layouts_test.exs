defmodule Bilimbi.Base.Tiling.SavedLayoutsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.TestFixtures, as: AuthzFixtures
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Scope
  alias Bilimbi.Base.Settings.TestFixtures, as: SettingsFixtures
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures
  alias Bilimbi.Base.Tiling.SavedLayouts
  alias Bilimbi.Base.Tiling.SharedLayouts

  @publish "ui.workspace.publish"
  @scope Scope.user(91, 73, 41)
  @other Scope.user(92, 73, 41)

  setup do
    SettingsFixtures.create_settings_table!()
    AuthzFixtures.create_authz_tables!()
    install_tiling_registry!()

    system = TenancyFixtures.scope(41, true)

    {:ok, :stored} =
      Authz.put_principal_capability(system, 73, :user, 91, @publish, true)

    on_exit(&ContributionRegistry.clear_for_test!/0)
    %{publisher: Authentication.sign_in(system, 91, 73), system: system}
  end

  test "an account starts with no layout and no default" do
    assert SavedLayouts.list(@scope) == []
    assert SavedLayouts.default_slug(@scope) == nil
    assert SavedLayouts.fetch(@scope, "orders") == :error
  end

  test "saving derives a slug, and a repeated label replaces the tree" do
    assert {:ok, entry} = SavedLayouts.save(@scope, "  Orders   desk ", "h.5(/companies,/users)")

    assert entry == %{
             "slug" => "orders-desk",
             "label" => "Orders desk",
             "layout" => "dwindle",
             "tree" => "h.5(/companies,/users)"
           }

    assert {:ok, replaced} = SavedLayouts.save(@scope, "Orders desk", "/companies")
    assert replaced["slug"] == "orders-desk"
    assert [%{"tree" => "/companies"}] = SavedLayouts.list(@scope)
    assert SavedLayouts.list(@other) == []
  end

  test "a label whose slug is taken gets a numbered slug" do
    {:ok, _} = SavedLayouts.save(@scope, "Orders", "/a")
    {:ok, second} = SavedLayouts.save(@scope, "orders!", "/b")

    assert second["slug"] == "orders-2"
    assert {:ok, ^second} = SavedLayouts.fetch(@scope, "orders-2")
  end

  test "refuses an empty label, an over-long label and an empty tree" do
    assert SavedLayouts.save(@scope, "   ", "/a") == {:error, :label}
    assert SavedLayouts.save(@scope, String.duplicate("x", 61), "/a") == {:error, :label}
    assert SavedLayouts.save(@scope, "Fine", "") == {:error, :tree}
    assert SavedLayouts.save(@scope, "Fine", "%2F%2Fevil.example%2Flogin") == {:error, :tree}
    assert SavedLayouts.save(@scope, "Fine", "%2F%09%2Fevil.example%2Flogin") == {:error, :tree}
  end

  test "rename keeps the slug, delete forgets the layout and its default" do
    {:ok, _} = SavedLayouts.save(@scope, "Orders", "/a")
    {:ok, _} = SavedLayouts.save(@scope, "People", "/b")

    assert :ok = SavedLayouts.set_default(@scope, "orders")
    assert SavedLayouts.default_slug(@scope) == "orders"
    assert SavedLayouts.set_default(@scope, "nope") == {:error, :not_found}

    assert {:ok, %{"slug" => "orders", "label" => "Orders today"}} =
             SavedLayouts.rename(@scope, "orders", "Orders today")

    assert SavedLayouts.rename(@scope, "nope", "x") == {:error, :not_found}
    assert SavedLayouts.rename(@scope, "orders", "") == {:error, :label}

    assert :ok = SavedLayouts.delete(@scope, "orders")
    assert Enum.map(SavedLayouts.list(@scope), & &1["slug"]) == ["people"]
    assert SavedLayouts.default_slug(@scope) == nil

    assert :ok = SavedLayouts.set_default(@scope, "people")
    assert :ok = SavedLayouts.set_default(@scope, nil)
    assert SavedLayouts.default_slug(@scope) == nil
  end

  test "shared workspaces stay in their company and filter by role code", %{publisher: publisher} do
    company = Scope.company(73)
    other_company = Scope.company(74)

    assert {:ok, %{"slug" => "company-desk"}} =
             SharedLayouts.publish(publisher, "Company desk", "/companies", [])

    assert {:ok, %{"slug" => "review-desk"}} =
             SharedLayouts.publish(publisher, "Review desk", "/users", ["reviewer"])

    assert Enum.map(SharedLayouts.visible(company, []), & &1["slug"]) == ["company-desk"]
    assert length(SharedLayouts.visible(company, ["reviewer"])) == 2
    assert SharedLayouts.fetch_visible(company, "review-desk", []) == :error
    assert SharedLayouts.list(other_company) == []

    assert SharedLayouts.publish(publisher, "Bad roles", "/users", ["Not A Code"]) ==
             {:error, :roles}

    assert SharedLayouts.publish(publisher, " ", "/users", []) == {:error, :label}
  end

  test "an account without a company sees no shared workspaces", %{publisher: publisher} do
    assert {:ok, _} = SharedLayouts.publish(publisher, "Company desk", "/companies", [])
    assert SharedLayouts.visible(nil, ["reviewer"]) == []
    assert SharedLayouts.fetch_visible(nil, "company-desk", []) == :error
  end

  test "publish and delete refuse a system actor and a user without the capability", %{
    system: system
  } do
    company = Scope.company(73)
    refused = Authentication.sign_in(system, 92, 73)

    for scope <- [system, refused] do
      assert {:error, :forbidden} = SharedLayouts.publish(scope, "Desk", "/companies", [])
      assert {:error, :forbidden} = SharedLayouts.delete(scope, "desk")
    end

    assert SharedLayouts.list(company) == []
  end

  test "a saved layout never takes the slug of a workspace route" do
    assert {:ok, %{"slug" => "shared-layouts-2"}} =
             SavedLayouts.save(@scope, "Shared layouts", "/companies")
  end

  test "each saved layout keeps its selected tiling mode and tree" do
    {:ok, _} = SavedLayouts.save(@scope, "Records", "/companies")
    {:ok, _} = SavedLayouts.save(@scope, "Lookups", "/users")

    assert {:ok, %{"layout" => "master", "tree" => "h.55(/companies,/users)"}} =
             SavedLayouts.set_layout(@scope, "records", "master", "h.55(/companies,/users)")

    assert {:ok, %{"layout" => "master"}} = SavedLayouts.fetch(@scope, "records")
    assert {:ok, %{"layout" => "dwindle"}} = SavedLayouts.fetch(@scope, "lookups")
    assert {:ok, %{"layout" => "master"}} = SavedLayouts.save(@scope, "Records", "/a")
    assert SavedLayouts.set_layout(@scope, "records", "grid", "/a") == {:error, :layout}
    assert SavedLayouts.set_layout(@scope, "records", "master", "") == {:error, :tree}

    assert SavedLayouts.set_layout(@scope, "missing", "master", "/a") ==
             {:error, :not_found}
  end

  defp install_tiling_registry! do
    %{settings: %{definitions: declared}, authz: authz} =
      Bilimbi.Base.Tiling.Contributions.contributions()

    definitions =
      Map.new(declared, fn {key, attributes} ->
        {key, Definition.new!(key, "base/tiling", attributes)}
      end)

    validated =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/tiling", otp_app: :bilimbi_base_tiling},
          payload: Map.put(authz, :company_directory, Bilimbi.Base.Tiling.TestCompanyDirectory)
        }
      ])

    ContributionRegistry.put_consumers_for_test!(
      %{
        settings: %{definitions: definitions, runtime_claims: []},
        authz: validated
      },
      "tiling-test"
    )
  end
end
