defmodule Bilimbi.Base.Authz.ContributionValidatorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Bilimbi.Base.Authz.ContributionValidator
  alias Bilimbi.Base.Authz.TestCompanyDirectory

  describe "shared verb vocabulary" do
    setup do
      finance =
        entry("finance/reconciliation", %{
          domains: %{"finance" => "Finance operations"},
          verbs: ["import"],
          capabilities: ["finance.reconciliation.statements.import"],
          roles: %{
            "tenant_owner" => %{capabilities: ["finance.reconciliation.statements.import"]}
          }
        })

      factory =
        entry("factory/production_execution", %{
          domains: %{"factory" => "Factory operations"},
          verbs: ["import"],
          capabilities: ["factory.production-execution.import"]
        })

      base = entry("base/authz", Bilimbi.Base.Authz.Contributions.contributions().authz)
      %{base: base, finance: finance, factory: factory}
    end

    test "each provider can register its vocabulary alone", context do
      for provider <- [context.finance, context.factory] do
        snapshot = ContributionValidator.validate_contributions!([context.base, provider])
        [capability] = provider.payload.capabilities

        assert Enum.count(snapshot.verbs, &(&1 == "import")) == 1
        assert snapshot.capability_owners[capability] == provider.descriptor.id
      end
    end

    test "both provider orders merge verbs without changing capability owners or role grants",
         context do
      snapshots =
        for providers <- [
              [context.finance, context.factory],
              [context.factory, context.finance]
            ] do
          snapshot = ContributionValidator.validate_contributions!([context.base | providers])

          assert snapshot.verbs == Enum.sort(Enum.uniq(snapshot.verbs))
          assert "import" in snapshot.verbs

          assert snapshot.capability_owners["finance.reconciliation.statements.import"] ==
                   "finance/reconciliation"

          assert snapshot.capability_owners["factory.production-execution.import"] ==
                   "factory/production_execution"

          assert snapshot.roles["tenant_owner"].capabilities == [
                   "admin.authz.field.manage",
                   "finance.reconciliation.statements.import"
                 ]

          assert snapshot.roles["core_admin"].grant_all
          snapshot
        end

      assert Enum.at(snapshots, 0) == Enum.at(snapshots, 1)
    end

    test "repeated vocabulary within a provider is idempotent", %{finance: finance} do
      repeated = put_in(finance.payload.verbs, ["import", "import"])
      repeated = put_in(repeated.payload.roles, %{})

      assert ContributionValidator.validate_contributions!([repeated]).verbs == ["import"]
    end

    test "shared verbs do not allow duplicate capability ownership", context do
      duplicate =
        put_in(context.factory, [:payload, :capabilities], [
          "finance.reconciliation.statements.import"
        ])

      for providers <- [[context.finance, duplicate], [duplicate, context.finance]] do
        first_owner = hd(providers).descriptor.id

        assert_raise ArgumentError,
                     "authz contribution from #{List.last(providers).descriptor.id} " <>
                       "capability finance.reconciliation.statements.import is already owned by #{first_owner}",
                     fn ->
                       ContributionValidator.validate_contributions!([context.base | providers])
                     end
      end
    end

    test "malformed verbs still fail after shared vocabulary was registered", context do
      for verb <- [nil, :import, 1, "", "Import", "with space", "trailing-", "two.parts"] do
        invalid = put_in(context.factory, [:payload, :verbs], ["import", verb])

        assert_raise ArgumentError, ~r/invalid verb/, fn ->
          ContributionValidator.validate_contributions!([context.base, context.finance, invalid])
        end
      end
    end

    test "verbs must be a list", context do
      for verbs <- [nil, "import", %{"import" => true}] do
        invalid = put_in(context.factory, [:payload, :verbs], verbs)

        assert_raise ArgumentError, ~r/verbs must be a list/, fn ->
          ContributionValidator.validate_contributions!([context.base, context.finance, invalid])
        end
      end
    end

    test "capabilities still require a registered verb", %{factory: factory} do
      unregistered = put_in(factory.payload.verbs, [])

      assert_raise ArgumentError, ~r/references unknown verb import/, fn ->
        ContributionValidator.validate_contributions!([unregistered])
      end
    end
  end

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
