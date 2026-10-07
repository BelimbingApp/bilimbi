defmodule Bilimbi.Base.Authz.ContributionValidatorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.FieldPolicy
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

  test "platform capabilities must also be registered capabilities" do
    assert_raise ArgumentError,
                 ~r/platform capability admin\.authz\.role\.view is not declared/,
                 fn ->
                   ContributionValidator.validate_contributions!([
                     entry("base/authz", %{
                       domains: %{"admin" => "Administrative operations"},
                       verbs: ["view"],
                       platform_capabilities: ["admin.authz.role.view"]
                     })
                   ])
                 end
  end

  describe "field policies" do
    @policy FieldPolicy.new!(tax_id: "admin.company.sensitive.view")
    @base %{
      domains: %{"admin" => "Administrative operations"},
      verbs: ["view"],
      capabilities: ["admin.company.sensitive.view"]
    }

    test "keeps each declared policy by its record type" do
      snapshot =
        ContributionValidator.validate_contributions!([
          entry("core/company", Map.put(@base, :field_policies, %{"Company" => @policy}))
        ])

      assert snapshot.field_policies == %{"Company" => @policy}
    end

    test "a snapshot with none declares none" do
      assert ContributionValidator.validate_contributions!([entry("core/company", @base)]).field_policies ==
               %{}
    end

    test "refuses a policy that names a capability nobody registered" do
      assert_raise ArgumentError,
                   ~r/field policy for Company references unknown capabilities/,
                   fn ->
                     ContributionValidator.validate_contributions!([
                       entry(
                         "core/company",
                         Map.merge(@base, %{
                           capabilities: [],
                           field_policies: %{"Company" => @policy}
                         })
                       )
                     ])
                   end
    end

    test "refuses a type two modules both declare, and a value that is not a policy" do
      assert_raise ArgumentError,
                   ~r/field policy for Company is already declared by core\/company/,
                   fn ->
                     ContributionValidator.validate_contributions!([
                       entry(
                         "core/company",
                         Map.put(@base, :field_policies, %{"Company" => @policy})
                       ),
                       entry("domain/other", %{field_policies: %{"Company" => @policy}})
                     ])
                   end

      assert_raise ArgumentError, ~r/must name a record type and carry a FieldPolicy/, fn ->
        ContributionValidator.validate_contributions!([
          entry("core/company", Map.put(@base, :field_policies, %{"Company" => [:tax_id]}))
        ])
      end
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
