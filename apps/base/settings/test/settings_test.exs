defmodule Bilimbi.Base.SettingsTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.ContributionValidator
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Scope

  import Bilimbi.Base.Settings.TestFixtures

  setup do
    create_settings_table!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  test "resolves user, company, tenant, and global overrides in order" do
    assert Settings.get("tests.inherited", Scope.user(10, 20, 30)) == "default"

    assert {:ok, "global"} = Settings.put("tests.inherited", "global")
    assert {:ok, "tenant"} = Settings.put("tests.inherited", "tenant", Scope.tenant(30))
    assert {:ok, "company"} = Settings.put("tests.inherited", "company", Scope.company(20, 30))
    assert {:ok, "user"} = Settings.put("tests.inherited", "user", Scope.user(10, 20, 30))

    assert Settings.get("tests.inherited", Scope.user(10, 20, 30)) == "user"
    assert Settings.get("tests.inherited", Scope.user(11, 20, 30)) == "company"
    assert Settings.get("tests.inherited", Scope.company(21, 30)) == "tenant"
    assert Settings.get("tests.inherited", Scope.tenant(31)) == "global"
  end

  test "rejects a definition key the settings column cannot store" do
    # The gap this closes: an over-long key was accepted here, appeared in the
    # registry, rendered on a settings screen, and failed only when a user
    # first pressed Save -- as far from the module that declared it as the
    # failure could land. Caught at contribution validation now, naming the
    # owner like every other malformed definition.
    overlong = String.duplicate("k", Bilimbi.Base.Settings.Schema.key_max_length() + 1)

    limit = Bilimbi.Base.Settings.Schema.key_max_length()

    assert_raise ArgumentError,
                 ~r/at most #{limit} characters.*declared by tests\/settings/,
                 fn ->
                   Definition.new!(overlong, "tests/settings", %{
                     type: :string,
                     scopes: [:global],
                     default: ""
                   })
                 end

    # The boundary itself is storable and must stay accepted.
    at_limit = String.duplicate("k", Bilimbi.Base.Settings.Schema.key_max_length())

    assert %Definition{} =
             Definition.new!(at_limit, "tests/settings", %{
               type: :string,
               scopes: [:global],
               default: ""
             })
  end

  test "distinguishes an absent declared row from an undeclared key" do
    assert Settings.get("tests.personal", Scope.user(10)) == "system"
    assert Settings.definition!("tests.personal").owner == "tests/settings"

    assert_raise ArgumentError, ~r/no discovered definition or runtime claim/, fn ->
      Settings.get("unknown.setting")
    end

    assert_raise ArgumentError, ~r/no discovered definition or runtime claim/, fn ->
      Settings.put("unknown.setting", "value")
    end
  end

  test "definitions enforce their exact scope and value type" do
    assert_raise ArgumentError, ~r/does not allow company scope/, fn ->
      Settings.put("tests.personal", "dark", Scope.company(20))
    end

    assert_raise ArgumentError, ~r/does not allow company scope/, fn ->
      Settings.overridden?("tests.personal", Scope.company(20))
    end

    assert_raise ArgumentError, ~r/does not allow company scope/, fn ->
      Settings.delete("tests.personal", Scope.company(20))
    end

    assert_raise ArgumentError, ~r/expects string/, fn ->
      Settings.put("tests.personal", 42, Scope.user(10))
    end

    assert {:ok, "dark"} = Settings.put("tests.personal", "dark", Scope.user(10))
    assert Settings.overridden?("tests.personal", Scope.user(10))
    assert :ok = Settings.delete("tests.personal", Scope.user(10))
    refute Settings.overridden?("tests.personal", Scope.user(10))
    assert Settings.get("tests.personal", Scope.user(10)) == "system"
  end

  test "claimed runtime state has no default and supports wildcard ownership" do
    assert Settings.get("tests.jobs.last_run") == nil

    assert {:ok, %{"status" => "ok"}} =
             Settings.put("tests.jobs.last_run", %{"status" => "ok"})

    assert Settings.get("tests.jobs.last_run") == %{"status" => "ok"}
  end

  test "encrypted definitions use a Laravel-compatible authenticated envelope" do
    secret = "postgresql://mirror-user:secret@example.test/database"
    assert {:ok, ^secret} = Settings.put("tests.secret", secret)

    %{rows: [[stored, true]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT value #>> '{}', is_encrypted FROM base_settings WHERE key = $1",
        ["tests.secret"]
      )

    refute stored =~ "mirror-user"
    assert Settings.get("tests.secret") == secret
  end

  test "the database prevents duplicate global rows" do
    assert {:ok, "first"} = Settings.put("tests.inherited", "first")

    assert_raise Postgrex.Error, fn ->
      Ecto.Adapters.SQL.query!(
        Repo,
        "INSERT INTO base_settings (key, value, is_encrypted) VALUES ($1, $2::json, false)",
        ["tests.inherited", Jason.encode!("second")]
      )
    end
  end

  test "consumer validation rejects duplicate definition and runtime-claim ownership" do
    entry = fn owner, payload ->
      %{descriptor: %{id: owner}, payload: payload}
    end

    definition = %{type: :string, scopes: [:global], default: "ok"}

    assert_raise ArgumentError, ~r/duplicate ownership: duplicate.key/, fn ->
      ContributionValidator.validate_contributions!([
        entry.("one", %{definitions: %{"duplicate.key" => definition}}),
        entry.("two", %{definitions: %{"duplicate.key" => definition}})
      ])
    end

    assert_raise ArgumentError, ~r/runtime setting claims have duplicate ownership/, fn ->
      ContributionValidator.validate_contributions!([
        entry.("one", %{runtime_claims: ["duplicate.*"]}),
        entry.("two", %{runtime_claims: ["duplicate.*"]})
      ])
    end
  end

  test "definition patterns choose the most specific owner" do
    assert %Definition{owner: "tests/specific", encrypted: false} =
             Settings.definition!("integrations.cloudflare.token.description")

    assert %Definition{owner: "tests/settings", encrypted: true} =
             Settings.definition!("integrations.cloudflare.token")
  end

  defp install_test_registry! do
    settings =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "tests/settings"},
          payload: %{
            definitions: %{
              "tests.inherited" => %{
                type: :string,
                scopes: [:user, :company, :tenant, :global],
                default: "default"
              },
              "tests.personal" => %{
                type: :string,
                scopes: [:user],
                default: "system"
              },
              "tests.secret" => %{
                type: :string,
                scopes: [:global],
                default: nil,
                nullable: true,
                encrypted: true
              },
              "integrations.*" => %{
                type: :string,
                scopes: [:global],
                default: nil,
                nullable: true,
                encrypted: true
              }
            },
            runtime_claims: ["tests.jobs.*"]
          }
        },
        %{
          descriptor: %{id: "tests/specific"},
          payload: %{
            definitions: %{
              "integrations.*.description" => %{
                type: :string,
                scopes: [:global],
                default: nil,
                nullable: true
              }
            }
          }
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "test",
      consumers: %{settings: settings, authz: [], menu: []}
    })
  end
end
