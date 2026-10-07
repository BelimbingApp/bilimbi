defmodule Bilimbi.Base.Authz.FieldPolicyTest do
  @moduledoc """
  Field-level authorization: a module declares which fields of a read model
  need a capability of their own, and a reader without it gets a withheld
  marker in the field's place, never the value.
  """

  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Authz.DecisionLog
  alias Bilimbi.Base.Authz.FieldPolicy
  alias Bilimbi.Base.Authz.Withheld
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.Tenancy.Authentication
  alias Bilimbi.Base.Tenancy.TestFixtures, as: TenancyFixtures

  import Bilimbi.Base.Authz.TestFixtures

  defmodule Record do
    @moduledoc false
    defstruct [:id, :name, :tax_id, :email]
  end

  @capability "admin.test.record.view"
  @policy FieldPolicy.new!(tax_id: @capability, email: @capability)

  setup do
    create_authz_tables!()
    install_test_registry!()
    on_exit(&ContributionRegistry.clear_for_test!/0)
    :ok
  end

  describe "FieldPolicy.new!/1" do
    test "keeps the declared fields and the distinct capabilities" do
      assert FieldPolicy.fields(@policy) == [:tax_id, :email]
      assert FieldPolicy.capabilities(@policy) == [@capability]
      assert FieldPolicy.capability!(@policy, :tax_id) == @capability

      assert_raise ArgumentError, ~r/does not name :name/, fn ->
        FieldPolicy.capability!(@policy, :name)
      end
    end

    test "refuses an invalid key, a non-atom field and a repeated field" do
      assert_raise ArgumentError, ~r/invalid capability key "nope"/, fn ->
        FieldPolicy.new!(tax_id: "nope")
      end

      assert_raise ArgumentError, ~r/entries are \{field_atom, capability\}/, fn ->
        FieldPolicy.new!(%{"tax_id" => @capability})
      end

      assert_raise ArgumentError, ~r/declares a field twice/, fn ->
        FieldPolicy.new!([{:tax_id, @capability}, {:tax_id, "admin.test.platform.manage"}])
      end
    end
  end

  describe "Authz.redact/3" do
    test "a reader holding the capability sees the values, with no decision logged" do
      assert record() == Authz.redact(holder(), @policy, record())
      assert [record()] == Authz.redact(holder(), @policy, [record()])
      assert Authz.withheld_fields(holder(), @policy) == []
      assert Repo.aggregate(DecisionLog, :count) == 0
    end

    test "a reader without it gets the marker in each sensitive field, and nothing is logged" do
      reader = signed_in_without()

      assert %Record{id: 1, name: "Acme", tax_id: withheld, email: withheld} =
               Authz.redact(reader, @policy, record())

      assert withheld == %Withheld{capability: @capability}
      assert Authz.withheld_fields(reader, @policy) == [:tax_id, :email]

      assert [%Record{tax_id: %Withheld{}}, %Record{email: %Withheld{}}] =
               Authz.redact(reader, @policy, [record(), record()])

      # Withholding a field is the shape of the read model for this reader,
      # not an attempt they made, so the decision log stays quiet.
      assert Repo.aggregate(DecisionLog, :count) == 0
    end

    test "an anonymous system scope names nobody and is withheld every field" do
      system = TenancyFixtures.scope()

      assert Authz.withheld_fields(system, @policy) == [:tax_id, :email]

      assert %Record{tax_id: %Withheld{}, email: %Withheld{}} =
               Authz.redact(system, @policy, record())
    end

    test "a policy that names a field the record lacks raises" do
      policy = FieldPolicy.new!(salary: @capability)

      assert_raise KeyError, fn -> Authz.redact(signed_in_without(), policy, record()) end
    end

    test "a direct deny withholds even when a grant-all role would allow" do
      scope = TenancyFixtures.scope()
      grant_role!(10, 7, "everything", true)
      assert Authz.withheld_fields(Authentication.sign_in(scope, 7, 10), @policy) == []

      assert {:ok, :stored} =
               Authz.put_principal_capability(scope, 10, :user, 7, @capability, false)

      assert Authz.withheld_fields(Authentication.sign_in(scope, 7, 10), @policy) ==
               [:tax_id, :email]
    end
  end

  describe "effective capabilities memory" do
    test "a second ask in the same process runs no statement, and a grant write is seen at once" do
      scope = TenancyFixtures.scope()
      reader = Authentication.sign_in(scope, 7, 10)

      first = capture_queries(fn -> Authz.withheld_fields(reader, @policy) end)
      assert first != []
      assert Authz.withheld_fields(reader, @policy) == [:tax_id, :email]

      assert capture_queries(fn -> Authz.withheld_fields(reader, @policy) end) == []

      assert {:ok, :stored} =
               Authz.put_principal_capability(scope, 10, :user, 7, @capability, true)

      assert Authz.withheld_fields(reader, @policy) == []

      {:ok, actor} = Authz.scope_actor(reader)
      assert @capability in Authz.effective_capabilities(actor).allowed
      assert capture_queries(fn -> Authz.effective_capabilities(actor) end) == []

      # Another process has no memory of this one.
      parent = self()

      spawn_link(fn ->
        send(
          parent,
          {:queries, capture_queries(fn -> Authz.withheld_fields(reader, @policy) end)}
        )
      end)

      assert_receive {:queries, queries}
      assert queries != []
    end
  end

  describe "Withheld" do
    test "renders as the word, never as the value, and is not a string" do
      withheld = %Withheld{capability: @capability}

      assert Withheld.withheld?(withheld)
      refute Withheld.withheld?("TAX-1")
      assert Phoenix.HTML.Safe.to_iodata(withheld) |> IO.iodata_to_binary() == "Withheld"
      assert_raise Protocol.UndefinedError, fn -> to_string(withheld) end
    end
  end

  describe "FieldPolicy.refuse_changes/2" do
    test "refuses a change to a withheld field and leaves other changes alone" do
      changeset =
        {%{tax_id: "TAX-1", email: "a@example.com", name: "Acme"},
         %{tax_id: :string, email: :string, name: :string}}
        |> Ecto.Changeset.cast(%{tax_id: "TAX-2", name: "Acme Ltd", email: "a@example.com"}, [
          :tax_id,
          :email,
          :name
        ])
        |> FieldPolicy.refuse_changes([:tax_id, :email])

      refute changeset.valid?

      assert changeset.errors == [
               tax_id: {"is withheld from this account and cannot be changed", []}
             ]

      assert Ecto.Changeset.get_change(changeset, :name) == "Acme Ltd"
    end

    test "passes a changeset that changes nothing withheld" do
      changeset =
        {%{tax_id: "TAX-1", name: "Acme"}, %{tax_id: :string, name: :string}}
        |> Ecto.Changeset.cast(%{name: "Acme Ltd"}, [:tax_id, :name])
        |> FieldPolicy.refuse_changes([:tax_id])

      assert changeset.valid?
    end
  end

  defp record, do: %Record{id: 1, name: "Acme", tax_id: "TAX-1", email: "acme@example.com"}

  defp capture_queries(fun) do
    handler = "field-policy-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:bilimbi, :base, :repo, :query],
      fn _, _, metadata, _ -> send(parent, {:field_policy_query, metadata.query}) end,
      nil
    )

    fun.()
    :telemetry.detach(handler)
    receive_queries([])
  end

  defp receive_queries(queries) do
    receive do
      {:field_policy_query, query} -> receive_queries([query | queries])
    after
      20 -> Enum.reverse(queries)
    end
  end

  defp holder do
    scope = TenancyFixtures.scope()
    assert {:ok, :stored} = Authz.put_principal_capability(scope, 10, :user, 7, @capability, true)
    Authentication.sign_in(scope, 7, 10)
  end

  defp signed_in_without, do: Authentication.sign_in(TenancyFixtures.scope(), 7, 10)
end
