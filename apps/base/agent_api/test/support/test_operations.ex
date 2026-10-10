defmodule Bilimbi.Base.AgentApi.TestOperations do
  @moduledoc false

  # A test domain of records, notes and one write, owned by this package so
  # the validator's ownership rule admits it. Each call reports back what it
  # was handed, so a test can see the handler ran, and with which scope.
  @behaviour Bilimbi.Base.AgentApi.Operation

  alias Bilimbi.Base.AgentApi.Page
  alias Bilimbi.Base.Authz.Restricted
  alias Bilimbi.Base.Tenancy.Scope

  def capabilities, do: ~w(admin.test.record.list admin.test.record.view admin.test.record.update)

  def payload do
    %{
      operations: [
        %{
          key: "base.agent_api.record.list",
          title: "List records",
          summary: "Find test records by label, one page at a time.",
          keywords: ["find", "search", "browse"],
          kind: :read,
          capability: "admin.test.record.list",
          input: %{
            "type" => "object",
            "properties" => %{
              "search" => %{"type" => "string", "maxLength" => 50},
              "page" => %{"type" => "integer", "minimum" => 1},
              "page_size" => %{"type" => "integer", "minimum" => 1}
            }
          },
          handler: __MODULE__
        },
        %{
          key: "base.agent_api.record.get",
          title: "Read a record",
          summary: "One test record by id.",
          keywords: ["show", "detail"],
          kind: :read,
          capability: "admin.test.record.view",
          input: %{
            "type" => "object",
            "required" => ["record_id"],
            "properties" => %{"record_id" => %{"type" => "integer", "minimum" => 1}}
          },
          output: %{"type" => "object"},
          handler: __MODULE__
        },
        %{
          key: "base.agent_api.record.update",
          title: "Change a record",
          summary: "Change a test record's label.",
          kind: :write,
          approval: :level,
          capability: "admin.test.record.update",
          input: %{
            "type" => "object",
            "required" => ["record_id", "label"],
            "properties" => %{
              "record_id" => %{"type" => "integer", "minimum" => 1},
              "label" => %{"type" => "string"}
            }
          },
          handler: __MODULE__
        }
      ],
      guides: [
        %{
          key: "base.agent_api.record",
          title: "Records",
          summary: "What a test record is.",
          capability: "admin.test.record.list",
          body: "A record carries a label and an amount. Archived records are hidden."
        }
      ]
    }
  end

  @impl true
  def call("base.agent_api.record.list", %Scope{}, input) do
    {:ok,
     %Page{
       entries: [%{id: 1, label: "First", archived?: false}],
       page: Map.get(input, "page", 1),
       page_size: Map.get(input, "page_size", 25),
       total: 1
     }}
  end

  def call("base.agent_api.record.get", %Scope{} = scope, %{"record_id" => id}) do
    case id do
      404 ->
        {:error, :not_found}

      409 ->
        {:error, {:invalid_transition, "archived"}}

      422 ->
        {:error,
         {%{}, %{label: :string}}
         |> Ecto.Changeset.cast(%{}, [:label])
         |> Ecto.Changeset.add_error(:label, "should be at most %{count} character(s)", count: 5)}

      _id ->
        {:ok,
         %{
           id: id,
           label: "Record #{id}",
           amount: Decimal.new("12.50"),
           secret: %Restricted{table_id: "records", field_id: "secret", roles: ["Finance"]},
           placed_on: ~D[2026-10-11],
           status: :open,
           tenant_id: Scope.tenant_id(scope)
         }}
    end
  end

  def call("base.agent_api.record.update", %Scope{}, _input) do
    raise "a write must never reach its handler while writes are not enabled"
  end

  @impl true
  def preview("base.agent_api.record.update", %Scope{}, %{"label" => label}) do
    {:ok, %{summary: "Change the label", changes: [%{field: "label", from: "Old", to: label}]}}
  end
end
