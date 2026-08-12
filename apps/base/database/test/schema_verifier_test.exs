defmodule Bilimbi.Base.Database.SchemaVerifierTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Database.SchemaVerifier
  alias Ecto.Adapters.SQL

  setup do
    schema =
      "schema_verifier_#{System.unique_integer([:positive, :monotonic])}"

    SQL.query!(Repo, ~s(CREATE SCHEMA "#{schema}"), [])
    create_tables!(schema)

    %{schema: schema}
  end

  test "accepts an exact column, index, and foreign-key contract", %{schema: schema} do
    assert :ok = SchemaVerifier.verify(Repo, [widget_spec()], prefix: schema)
  end

  test "reports missing tables and structural drift", %{schema: schema} do
    assert {:error, [missing]} =
             SchemaVerifier.verify(Repo, [%{widget_spec() | name: "missing_widgets"}],
               prefix: schema
             )

    assert missing == "missing table #{schema}.missing_widgets"

    drifted =
      widget_spec()
      |> put_in([:columns, "name", :nullable], true)
      |> put_in([:indexes, "widgets_name_unique", :unique], false)
      |> put_in([:foreign_keys, "widgets_parent_foreign", :on_delete], :cascade)

    assert {:error, errors} = SchemaVerifier.verify(Repo, [drifted], prefix: schema)
    assert "widgets.name: expected nullable=true, got false" in errors
    assert "widgets: incompatible index widgets_name_unique" in errors
    assert "widgets: incompatible foreign key widgets_parent_foreign" in errors
  end

  test "rejects partial optional contributions", %{schema: schema} do
    spec =
      widget_spec()
      |> Map.put(:optional_indexes, %{
        "widgets_parent_id_index" => index(["parent_id"])
      })
      |> Map.put(:optional_groups, [
        %{
          name: "parent lookup",
          columns: [],
          indexes: ["widgets_parent_id_index"],
          foreign_keys: ["widgets_parent_foreign"]
        }
      ])

    assert {:error, errors} = SchemaVerifier.verify(Repo, [spec], prefix: schema)
    assert "widgets: incomplete optional contribution parent lookup" in errors
  end

  test "verifies foreign-key update actions", %{schema: schema} do
    drifted =
      put_in(
        widget_spec(),
        [:foreign_keys, "widgets_parent_foreign", :on_update],
        :cascade
      )

    assert {:error, errors} = SchemaVerifier.verify(Repo, [drifted], prefix: schema)
    assert "widgets: incompatible foreign key widgets_parent_foreign" in errors
  end

  test "accepts uuid, char, jsonb, and inet columns", %{schema: schema} do
    assert :ok = SchemaVerifier.verify(Repo, [gadget_spec()], prefix: schema)
  end

  test "reports drift on uuid, char, jsonb, and inet columns", %{schema: schema} do
    drifted =
      gadget_spec()
      |> put_in([:columns, "id", :type], :bigint)
      |> put_in([:columns, "url_hash", :type], {:char, 16})
      |> put_in([:columns, "payload", :type], :json)
      |> put_in([:columns, "ip_address", :type], {:varchar, 45})

    assert {:error, errors} = SchemaVerifier.verify(Repo, [drifted], prefix: schema)

    assert "gadgets.id: incompatible type" in errors
    assert "gadgets.url_hash: incompatible type" in errors
    assert "gadgets.payload: incompatible type" in errors
    assert "gadgets.ip_address: incompatible type" in errors
  end

  test "reports an unmodelled contract type instead of raising", %{schema: schema} do
    spec = put_in(widget_spec(), [:columns, "name", :type], :money)

    assert {:error, errors} = SchemaVerifier.verify(Repo, [spec], prefix: schema)
    assert "widgets.name: incompatible type" in errors
  end

  test "rejects unsafe PostgreSQL identifiers" do
    assert_raise ArgumentError, ~r/invalid PostgreSQL identifier/, fn ->
      SchemaVerifier.quote_identifier!("public; DROP SCHEMA public")
    end
  end

  defp create_tables!(schema) do
    SQL.query!(Repo, ~s|CREATE TABLE "#{schema}".parents (id bigint PRIMARY KEY)|, [])

    SQL.query!(
      Repo,
      """
      CREATE TABLE "#{schema}".widgets (
        id bigserial PRIMARY KEY,
        parent_id bigint,
        name varchar(20) NOT NULL DEFAULT 'ready',
        enabled boolean NOT NULL DEFAULT false,
        CONSTRAINT widgets_parent_foreign
          FOREIGN KEY (parent_id)
          REFERENCES "#{schema}".parents (id)
          ON DELETE RESTRICT
      )
      """,
      []
    )

    SQL.query!(
      Repo,
      ~s|CREATE UNIQUE INDEX widgets_name_unique ON "#{schema}".widgets (name)|,
      []
    )

    # Mirrors the Belimbing types no contract could express before:
    # notifications.id (uuid), user_pins.url_hash (char), the audit tables'
    # jsonb payloads, and their ipAddress() column, which Laravel 13 emits as
    # inet rather than varchar(45).
    SQL.query!(
      Repo,
      """
      CREATE TABLE "#{schema}".gadgets (
        id uuid PRIMARY KEY,
        url_hash char(32) NOT NULL,
        payload jsonb,
        ip_address inet
      )
      """,
      []
    )
  end

  defp widget_spec do
    %{
      name: "widgets",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "widgets_id_seq"}),
        "parent_id" => column(:bigint),
        "name" => column({:varchar, 20}, false, {:string, "ready"}),
        "enabled" => column(:boolean, false, {:boolean, false})
      },
      indexes: %{
        "widgets_pkey" => index(["id"], true),
        "widgets_name_unique" => index(["name"], true)
      },
      foreign_keys: %{
        "widgets_parent_foreign" => %{
          columns: ["parent_id"],
          references: {"parents", ["id"]},
          on_delete: :restrict
        }
      }
    }
  end

  defp gadget_spec do
    %{
      name: "gadgets",
      columns: %{
        "id" => column(:uuid, false),
        "url_hash" => column({:char, 32}, false),
        "payload" => column(:jsonb),
        "ip_address" => column(:inet)
      },
      indexes: %{
        "gadgets_pkey" => index(["id"], true)
      },
      foreign_keys: %{}
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false) do
    %{columns: columns, unique: unique, where: nil}
  end
end
