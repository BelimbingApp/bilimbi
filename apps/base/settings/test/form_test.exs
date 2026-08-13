defmodule Bilimbi.Base.Settings.FormTest do
  @moduledoc """
  The rules a settings screen cannot see itself getting wrong: clearing that
  silently pins a value, inherited values that look set, and secrets that
  round-trip through the browser.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.ContributionValidator
  alias Bilimbi.Base.Settings.Form
  alias Bilimbi.Base.Settings.Scope

  import Bilimbi.Base.Settings.TestFixtures

  @user Scope.user(10, 20, 30)

  setup do
    create_settings_table!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  defp field(fields, key), do: Enum.find(fields, &(&1.key == key))

  describe "fields/2" do
    test "builds the screen from declared definitions, not a hand-written list" do
      fields = Form.fields(["profile"], @user)

      assert Enum.map(fields, & &1.key) == ["tests.landing", "tests.theme"]
      assert field(fields, "tests.theme").definition.label == "Theme"
    end

    test "keeps the caller's group order and sorts by key inside a group" do
      fields = Form.fields(["appearance", "profile"], @user)

      assert Enum.map(fields, & &1.key) == ["tests.density", "tests.landing", "tests.theme"]
    end

    test "a group nothing declares yields no fields rather than raising" do
      assert Form.fields(["nope"], @user) == []
    end

    test "groups/0 lists what screens may ask for" do
      assert Form.groups() == ["appearance", "operator", "profile"]
    end

    test "reports a value as inherited until it is set at this scope" do
      assert {:ok, "dark"} = Settings.put("tests.theme", "dark", Scope.tenant(30))

      inherited = field(Form.fields(["profile"], @user), "tests.theme")
      assert inherited.value == "dark"
      refute inherited.overridden?
      assert inherited.source_scope == :tenant

      assert {:ok, "light"} = Settings.put("tests.theme", "light", @user)

      own = field(Form.fields(["profile"], @user), "tests.theme")
      assert own.value == "light"
      assert own.overridden?
      assert own.source_scope == :user
    end

    test "falls back to the definition's default with no override anywhere" do
      untouched = field(Form.fields(["profile"], @user), "tests.theme")

      assert untouched.value == "system"
      refute untouched.overridden?
      assert untouched.source_scope == :global
    end

    test "resolves a definition at the nearest scope it actually allows" do
      # The screen is user-scoped; this setting is global-only. Reading it at
      # the user scope would ask a question the registry cannot answer.
      assert {:ok, 30} = Settings.put("tests.retention", 30)

      global_only = field(Form.fields(["operator"], @user), "tests.retention")
      assert global_only.value == 30
      assert global_only.source_scope == :global
    end

    test "shows a stored secret as a mask and never its value" do
      assert {:ok, _} = Settings.put("tests.secret", "hunter2")

      secret = field(Form.fields(["operator"], nil), "tests.secret")
      assert secret.value == Form.secret_mask()
      refute secret.value =~ "hunter2"
      assert secret.encrypted?
    end

    test "shows an unset secret as empty, not as a mask" do
      # A mask on an empty field would claim a secret is stored when none is.
      assert field(Form.fields(["operator"], nil), "tests.secret").value == ""
    end
  end

  describe "save/3" do
    test "writes a submitted value" do
      fields = Form.fields(["profile"], @user)

      assert {:ok, %{written: ["tests.theme"]}} =
               Form.save(%{"tests.theme" => "dark"}, fields, @user)

      assert Settings.get("tests.theme", @user) == "dark"
    end

    test "leaves a field absent from the submission alone" do
      assert {:ok, "dark"} = Settings.put("tests.theme", "dark", @user)
      fields = Form.fields(["profile"], @user)

      assert {:ok, %{written: ["tests.landing"]}} =
               Form.save(%{"tests.landing" => "/dashboard"}, fields, @user)

      assert Settings.get("tests.theme", @user) == "dark"
    end

    test "a blank clears the override instead of pinning an empty value" do
      assert {:ok, "tenant-wide"} = Settings.put("tests.theme", "tenant-wide", Scope.tenant(30))
      assert {:ok, "mine"} = Settings.put("tests.theme", "mine", @user)

      fields = Form.fields(["profile"], @user)
      assert {:ok, %{cleared: ["tests.theme"]}} = Form.save(%{"tests.theme" => ""}, fields, @user)

      # The value returns to what it inherits. Writing "" would have pinned an
      # empty string here and shadowed the tenant value for good.
      refute Settings.overridden?("tests.theme", @user)
      assert Settings.get("tests.theme", @user) == "tenant-wide"
    end

    test "clearing an already-inherited field reports unchanged, not cleared" do
      fields = Form.fields(["profile"], @user)

      assert {:ok, %{cleared: [], unchanged: ["tests.theme"]}} =
               Form.save(%{"tests.theme" => ""}, fields, @user)
    end

    test "an untouched secret still holding the mask is not written back" do
      assert {:ok, _} = Settings.put("tests.secret", "hunter2")
      fields = Form.fields(["operator"], nil)

      assert {:ok, %{unchanged: ["tests.secret"], written: []}} =
               Form.save(%{"tests.secret" => Form.secret_mask()}, fields, nil)

      assert Settings.get("tests.secret") == "hunter2"
    end

    test "a genuinely changed secret is written" do
      assert {:ok, _} = Settings.put("tests.secret", "hunter2")
      fields = Form.fields(["operator"], nil)

      assert {:ok, %{written: ["tests.secret"]}} =
               Form.save(%{"tests.secret" => "correct-horse"}, fields, nil)

      assert Settings.get("tests.secret") == "correct-horse"
    end

    test "refuses a value that cannot be the declared type, naming the field" do
      # Settings.put/3 raises on a wrong type -- correct for a module API, fatal
      # for a form, since every browser submission arrives as a string.
      fields = Form.fields(["operator"], @user)

      assert {:error, "tests.retention", "must be a whole number"} =
               Form.save(%{"tests.retention" => "not-an-integer"}, fields, @user)

      # And it did not half-apply: nothing was written.
      refute Settings.overridden?("tests.retention", nil)
    end

    test "casts a submitted string to the declared type" do
      fields = Form.fields(["operator"], @user)

      assert {:ok, %{written: ["tests.retention"]}} =
               Form.save(%{"tests.retention" => " 45 "}, fields, @user)

      assert Settings.get("tests.retention") == 45
    end

    test "refuses rather than coercing, where Belimbing's PHP cast would not" do
      # (int) "12abc" is 12 in PHP and would save a number the user never
      # typed. Laravel validation catches it there; nothing does here.
      %{definition: definition} = Form.fields(["operator"], @user) |> Enum.at(0)

      assert Form.cast("12abc", definition) == {:error, "must be a whole number"}
      assert Form.cast("12", definition) == {:ok, 12}
    end
  end

  describe "restore_defaults/2" do
    test "drops this scope's overrides and leaves inherited values standing" do
      assert {:ok, "tenant-wide"} = Settings.put("tests.theme", "tenant-wide", Scope.tenant(30))
      assert {:ok, "mine"} = Settings.put("tests.theme", "mine", @user)
      assert {:ok, "/mine"} = Settings.put("tests.landing", "/mine", @user)

      fields = Form.fields(["profile"], @user)
      assert {:ok, cleared} = Form.restore_defaults(fields, @user)
      assert Enum.sort(cleared) == ["tests.landing", "tests.theme"]

      refute Settings.overridden?("tests.theme", @user)
      assert Settings.get("tests.theme", @user) == "tenant-wide"
    end

    test "does not write the defaults as overrides" do
      assert {:ok, "mine"} = Settings.put("tests.theme", "mine", @user)

      fields = Form.fields(["profile"], @user)
      assert {:ok, ["tests.theme"]} = Form.restore_defaults(fields, @user)

      # Writing the default would create an override that merely equals the
      # default today and would stop tracking it if the default ever changed.
      refute Settings.overridden?("tests.theme", @user)
      assert Settings.get("tests.theme", @user) == "system"
    end
  end

  defp install_test_registry! do
    settings =
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "tests/settings"},
          payload: %{
            definitions: %{
              "tests.theme" => %{
                type: :string,
                scopes: [:user, :company, :tenant, :global],
                default: "system",
                label: "Theme",
                help: "Light, dark, or operating-system controlled.",
                editable: "profile"
              },
              "tests.landing" => %{
                type: :string,
                scopes: [:user],
                default: "",
                label: "Landing page",
                help: "The first page opened after sign-in.",
                editable: "profile"
              },
              "tests.density" => %{
                type: :string,
                scopes: [:user],
                default: "comfortable",
                label: "Density",
                help: "How tightly rows are packed.",
                editable: "appearance"
              },
              "tests.retention" => %{
                type: :integer,
                scopes: [:global],
                default: 90,
                label: "Retention",
                help: "Days to retain decision logs.",
                editable: "operator"
              },
              "tests.secret" => %{
                type: :string,
                scopes: [:global],
                default: nil,
                nullable: true,
                encrypted: true,
                label: "API token",
                help: "Credential for the upstream service.",
                editable: "operator"
              },
              "tests.hidden" => %{
                type: :string,
                scopes: [:global],
                default: "x"
              }
            },
            runtime_claims: []
          }
        }
      ])

    ContributionRegistry.put_snapshot_for_test!(%{
      graph_fingerprint: "test",
      consumers: %{settings: settings, authz: [], menu: []}
    })
  end
end
