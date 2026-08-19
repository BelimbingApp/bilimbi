defmodule Bilimbi.Base.Authz.CapabilitiesTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.CapabilitySummary
  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.Page
  alias Bilimbi.Base.Authz.TestCompanyDirectory
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry

  setup do
    authz =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{
            id: "base/authz",
            otp_app: :bilimbi_base_authz
          },
          payload: %{
            domains: %{"admin" => "Administrative operations", "system" => "System ops"},
            verbs: ["view", "list", "create", "delete"],
            capabilities: [
              "admin.authz.role.list",
              "admin.authz.role.view",
              "system.audit.log.list"
            ],
            roles: %{
              "all_access" => %{name: "All Access", grant_all: true}
            },
            company_directory: TestCompanyDirectory
          }
        },
        %{
          descriptor: %{
            id: "core/user",
            otp_app: :bilimbi_core_user
          },
          payload: %{
            domains: %{},
            verbs: [],
            capabilities: [
              "admin.user.create",
              "admin.user.delete",
              "admin.user.list"
            ],
            roles: %{}
          }
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "authz-capabilities-test",
      consumers: %{settings: [], authz: authz, menu: []}
    })

    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "lists registered capabilities with parsed fields and humanized modules" do
    assert %Page{entries: entries, total_entries: 6, total_pages: 1, page: 1, page_size: 25} =
             Authz.list_capabilities()

    assert length(entries) == 6

    first = Enum.find(entries, &(&1.key == "admin.user.create"))

    assert first == %CapabilitySummary{
             id: "admin.user.create",
             key: "admin.user.create",
             domain: "admin",
             resource: "user",
             action: "create",
             module: "Core / User"
           }

    second = Enum.find(entries, &(&1.key == "admin.authz.role.list"))

    assert second == %CapabilitySummary{
             id: "admin.authz.role.list",
             key: "admin.authz.role.list",
             domain: "admin",
             resource: "authz.role",
             action: "list",
             module: "Base / Authz"
           }
  end

  test "returns unique sorted capability domains" do
    assert Authz.capability_domains() == ["admin", "system"]
  end

  test "filters capabilities by search matching key or module" do
    # Matching key
    page = Authz.list_capabilities(search: "audit")
    assert Enum.map(page.entries, & &1.key) == ["system.audit.log.list"]

    # Matching module name
    page_user = Authz.list_capabilities(search: "core / user")

    assert Enum.map(page_user.entries, & &1.key) == [
             "admin.user.create",
             "admin.user.delete",
             "admin.user.list"
           ]

    # No match
    empty_page = Authz.list_capabilities(search: "nonexistent")
    assert empty_page.entries == []
    assert empty_page.total_entries == 0
    assert empty_page.total_pages == 0
  end

  test "filters capabilities by domain" do
    page = Authz.list_capabilities(domain: "system")
    assert Enum.map(page.entries, & &1.key) == ["system.audit.log.list"]
    assert page.total_entries == 1

    admin_page = Authz.list_capabilities(domain: "admin")
    assert length(admin_page.entries) == 5
  end

  test "sorts capabilities by key, domain, resource, action, and module" do
    # Sort by action asc
    asc_actions = Authz.list_capabilities(sort_by: :action, sort_dir: :asc)
    actions = Enum.map(asc_actions.entries, & &1.action)
    assert actions == Enum.sort(actions)

    # Sort by action desc
    desc_actions = Authz.list_capabilities(sort_by: :action, sort_dir: :desc)
    actions_desc = Enum.map(desc_actions.entries, & &1.action)
    assert actions_desc == Enum.reverse(Enum.sort(actions))

    # Sort by module asc
    asc_modules = Authz.list_capabilities(sort_by: :module, sort_dir: :asc)
    assert hd(asc_modules.entries).module == "Base / Authz"

    # Sort by module desc
    desc_modules = Authz.list_capabilities(sort_by: :module, sort_dir: :desc)
    assert hd(desc_modules.entries).module == "Core / User"
  end

  test "paginates capability results" do
    page1 = Authz.list_capabilities(page: 1, page_size: 2)
    assert length(page1.entries) == 2
    assert page1.page == 1
    assert page1.page_size == 2
    assert page1.total_entries == 6
    assert page1.total_pages == 3

    page2 = Authz.list_capabilities(page: 2, page_size: 2)
    assert length(page2.entries) == 2
    assert page2.page == 2

    # Disjoint pages
    assert MapSet.disjoint?(
             MapSet.new(Enum.map(page1.entries, & &1.key)),
             MapSet.new(Enum.map(page2.entries, & &1.key))
           )
  end
end
