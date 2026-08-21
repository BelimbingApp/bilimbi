defmodule Bilimbi.Base.Audit.MutationCaptureTest do
  use Bilimbi.Base.Database.DataCase, async: false

  alias Bilimbi.Base.Audit
  alias Bilimbi.Base.Audit.Context
  alias Bilimbi.Base.Audit.MutationCapture
  alias Bilimbi.Base.Audit.MutationSchema
  alias Bilimbi.Base.Audit.TestFixtures
  alias Ecto.Adapters.SQL

  defmodule Widget do
    use Ecto.Schema

    import Ecto.Changeset

    schema "capture_widgets" do
      field :name, :string
      field :password, :string
      field :notes, :string
      field :tenant_id, :id
    end

    def changeset(widget, attributes),
      do: cast(widget, attributes, [:name, :password, :notes, :tenant_id])
  end

  setup tags do
    unless tags[:without_audit_tables], do: TestFixtures.create_audit_tables!()

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE IF NOT EXISTS capture_widgets (
        id bigserial PRIMARY KEY,
        name varchar(255),
        password varchar(255),
        notes text,
        tenant_id bigint
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    previous = Application.get_env(:bilimbi_base_database, :write_capture)
    Application.put_env(:bilimbi_base_database, :write_capture, MutationCapture)

    on_exit(fn ->
      Application.put_env(:bilimbi_base_database, :write_capture, previous)
      Context.put(nil)
    end)

    :ok
  end

  defp mutations do
    Repo.all(MutationSchema)
  end

  test "an insert writes a canonical guest row with the row's own tenant" do
    Repo.insert!(Widget.changeset(%Widget{}, %{name: "First", tenant_id: 41}))

    assert [row] = mutations()
    assert row.event == "created"
    assert row.source == "listener"
    assert row.actor_type == "guest"
    assert row.actor_id == 0
    assert row.tenant_id == 41
    assert row.auditable_type == inspect(Widget)
    assert row.auditable_id != nil
    assert row.old_values == nil or row.old_values == %{}
    assert row.new_values["name"] == "First"
  end

  test "the process context supplies the actor and the row's tenant still wins" do
    Context.put(%Context{
      actor_type: "user",
      actor_id: 91,
      company_id: 73,
      tenant_id: 99,
      url: "/widgets",
      trace_id: "abc123"
    })

    Repo.insert!(Widget.changeset(%Widget{}, %{name: "Second", tenant_id: 41}))

    assert [row] = mutations()
    assert row.actor_type == "user"
    assert row.actor_id == 91
    assert row.company_id == 73
    # Row tenant is ground truth over the context's 99.
    assert row.tenant_id == 41
    assert row.url == "/widgets"
    assert row.trace_id == "abc123"
  end

  test "a tenant-less row falls back to the context tenant" do
    Context.put(%Context{actor_type: "user", actor_id: 91, tenant_id: 41})

    Repo.insert!(Widget.changeset(%Widget{}, %{name: "NoTenant"}))

    assert [row] = mutations()
    assert row.tenant_id == 41
  end

  test "updates record changed fields only, with originals" do
    widget =
      Repo.insert!(Widget.changeset(%Widget{}, %{name: "Old", notes: "keep", tenant_id: 41}))

    Repo.update!(Widget.changeset(widget, %{name: "New"}))

    assert [_created, updated] = Enum.sort_by(mutations(), & &1.id)
    assert updated.event == "updated"
    assert updated.old_values == %{"name" => "Old"}
    assert updated.new_values == %{"name" => "New"}
    refute Map.has_key?(updated.new_values, "notes")
  end

  test "a no-change update writes nothing" do
    widget = Repo.insert!(Widget.changeset(%Widget{}, %{name: "Same", tenant_id: 41}))

    Repo.update!(Widget.changeset(widget, %{name: "Same"}))

    assert [%{event: "created"}] = mutations()
  end

  test "deletes record the old attributes" do
    widget = Repo.insert!(Widget.changeset(%Widget{}, %{name: "Doomed", tenant_id: 41}))

    Repo.delete!(widget)

    assert [_created, deleted] = Enum.sort_by(mutations(), & &1.id)
    assert deleted.event == "deleted"
    assert deleted.old_values["name"] == "Doomed"
    assert deleted.new_values == nil or deleted.new_values == %{}
  end

  test "redacted fields record the change, never the value; long strings truncate" do
    long = String.duplicate("x", 2100)

    widget =
      Repo.insert!(
        Widget.changeset(%Widget{}, %{name: "R", password: "hunter2", notes: long, tenant_id: 41})
      )

    Repo.update!(Widget.changeset(widget, %{password: "hunter3"}))

    assert [created, updated] = Enum.sort_by(mutations(), & &1.id)
    assert created.new_values["password"] == "[redacted]"
    assert created.new_values["notes"] =~ "[truncated 2100 chars]"
    refute created.new_values["notes"] =~ String.duplicate("x", 2001)
    assert updated.old_values["password"] == "[redacted]"
    assert updated.new_values["password"] == "[redacted]"
  end

  test "audit's own rows and configured exclusions are never captured" do
    {:ok, scope} = fake_scope(41)
    assert {:ok, _mutation} = Audit.record_mutation(scope, explicit_attributes())
    # The explicit row exists; no listener row about it does.
    assert [%{source: "explicit"}] = mutations()

    previous = Application.get_env(:bilimbi_base_audit, :exclude_schemas)
    Application.put_env(:bilimbi_base_audit, :exclude_schemas, [Widget])
    on_exit(fn -> Application.put_env(:bilimbi_base_audit, :exclude_schemas, previous || []) end)

    Repo.insert!(Widget.changeset(%Widget{}, %{name: "Excluded", tenant_id: 41}))
    assert [%{source: "explicit"}] = mutations()
  end

  test "without_auditing suppresses capture" do
    Audit.without_auditing(fn ->
      Repo.insert!(Widget.changeset(%Widget{}, %{name: "Quiet", tenant_id: 41}))
    end)

    assert mutations() == []
  end

  @tag :without_audit_tables
  test "a missing audit table is the silent pre-canonical state and never aborts the caller" do
    Repo.transaction(fn ->
      widget = Repo.insert!(Widget.changeset(%Widget{}, %{name: "Early", tenant_id: 41}))
      # The transaction stays healthy after the capture's savepoint rollback.
      assert %Widget{} = Repo.update!(Widget.changeset(widget, %{name: "Still fine"}))
    end)

    assert Repo.get_by(Widget, name: "Still fine")
  end

  defp fake_scope(tenant_id) do
    {:ok,
     %Bilimbi.Base.Tenancy.Scope{
       tenant: %Bilimbi.Base.Tenancy.Identity{
         id: tenant_id,
         name: "T",
         status: "active",
         is_platform_operator: false
       }
     }}
  end

  defp explicit_attributes do
    %{
      actor_type: "user",
      actor_id: 91,
      auditable_type: "Widget",
      auditable_id: "1",
      source: "explicit",
      event: "created",
      occurred_at: NaiveDateTime.utc_now()
    }
  end
end
