defmodule Bilimbi.Base.Authz.ContributionValidatorTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Authz.ContributionValidator

  test "merges role capabilities after validating the complete provider graph" do
    snapshot =
      ContributionValidator.validate_contributions!([
        entry("base/authz", %{
          domains: %{"admin" => "Administrative operations"},
          verbs: ["view"],
          capabilities: ["admin.authz.role.view"],
          roles: %{"viewer" => %{name: "Viewer"}}
        }),
        entry("core/company", %{
          capabilities: ["admin.company.view"],
          roles: %{"viewer" => %{capabilities: ["admin.company.view"]}}
        }),
        entry("core/user", %{
          roles: %{"viewer" => %{capabilities: ["admin.authz.role.view"]}}
        })
      ])

    assert snapshot.capabilities == ["admin.authz.role.view", "admin.company.view"]

    assert snapshot.roles["viewer"].capabilities == [
             "admin.authz.role.view",
             "admin.company.view"
           ]
  end

  test "rejects duplicate capability ownership and unknown role capabilities" do
    base =
      entry("base/authz", %{
        domains: %{"admin" => "Administrative operations"},
        verbs: ["view"],
        capabilities: ["admin.authz.role.view"]
      })

    assert_raise ArgumentError, ~r/already owned by base\/authz/, fn ->
      ContributionValidator.validate_contributions!([
        base,
        entry("core/company", %{capabilities: ["admin.authz.role.view"]})
      ])
    end

    assert_raise ArgumentError, ~r/references unknown capabilities: admin.company.view/, fn ->
      ContributionValidator.validate_contributions!([
        base,
        entry("core/company", %{
          roles: %{
            "viewer" => %{name: "Viewer", capabilities: ["admin.company.view"]}
          }
        })
      ])
    end
  end

  test "rejects malformed keys and grant-all roles with enumerated grants" do
    assert_raise ArgumentError, ~r/invalid capability key/, fn ->
      ContributionValidator.validate_contributions!([
        entry("base/authz", %{capabilities: ["Admin.role.view"]})
      ])
    end

    assert_raise ArgumentError, ~r/combines grant_all and grants/, fn ->
      ContributionValidator.validate_contributions!([
        entry("base/authz", %{
          domains: %{"admin" => "Administrative operations"},
          verbs: ["view"],
          capabilities: ["admin.authz.role.view"],
          roles: %{
            "administrator" => %{
              name: "Administrator",
              grant_all: true,
              capabilities: ["admin.authz.role.view"]
            }
          }
        })
      ])
    end
  end

  defp entry(owner, payload), do: %{descriptor: %{id: owner}, payload: payload}
end
