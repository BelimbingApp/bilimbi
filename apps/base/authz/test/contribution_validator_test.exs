defmodule Bilimbi.Base.Authz.ContributionValidatorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.TestCompanyDirectory

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

  describe "company directory contract" do
    test "accepts a directory that answers every question the contract asks" do
      snapshot =
        ContributionValidator.validate_contributions!([
          %{
            descriptor: %{id: "base/authz", otp_app: :bilimbi_base_authz},
            payload: %{company_directory: TestCompanyDirectory}
          }
        ])

      assert snapshot.company_directory == TestCompanyDirectory
    end

    test "rejects a directory that cannot name the companies it lists" do
      # Defined at run time on purpose. A module carrying `@behaviour` without
      # `companies_in_scope/1` is a compile *warning*, and this package builds
      # with `--warnings-as-errors`, so the incomplete directory cannot live in
      # `test/support` -- it would fail the build rather than this assertion.
      # Evaluating it here keeps the warning at run time, where `capture_io`
      # swallows it and the validator still gets a real module to inspect.
      capture_io(:stderr, fn ->
        Code.eval_string(~S"""
        defmodule IdsOnlyCompanyDirectory do
          @behaviour Bilimbi.Base.Authz.CompanyDirectory

          @impl true
          def company_ids(_scope), do: [10]

          @impl true
          def company_in_scope?(_scope, company_id), do: company_id == 10
        end
        """)
      end)

      assert_raise ArgumentError, ~r/company directory .* has the wrong contract/, fn ->
        ContributionValidator.validate_contributions!([
          %{
            descriptor: %{id: "base/authz", otp_app: :bilimbi_base_authz},
            payload: %{company_directory: IdsOnlyCompanyDirectory}
          }
        ])
      end
    end
  end

  defp entry(owner, payload), do: %{descriptor: %{id: owner}, payload: payload}
end
