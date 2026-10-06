defmodule Bilimbi.Base.Grid.TestSources do
  @moduledoc """
  A small test-only domain the grid tests walk: orders placed by customers
  in countries, with order lines and tags. Base cannot depend on a Core
  module to prove the catalog, so it owns the smallest shape that has a
  one-link chain, a many-link on a key pair, a many-link through an edge
  table, a string key, and two tenants.
  """

  import Ecto.Query

  alias Bilimbi.Base.Tenancy

  defmodule Orders do
    @moduledoc false
    @behaviour Bilimbi.Base.Grid.Source

    import Ecto.Query

    @impl true
    def query(scope) do
      from(o in Tenancy.scope_query("grid_test_orders", scope),
        select: %{
          id: o.id,
          label: o.label,
          amount: o.amount,
          status: o.status,
          placed_at: o.placed_at,
          customer_id: o.customer_id
        }
      )
    end
  end

  defmodule Customers do
    @moduledoc false
    @behaviour Bilimbi.Base.Grid.Source

    import Ecto.Query

    @impl true
    def query(scope) do
      from(c in Tenancy.scope_query("grid_test_customers", scope),
        select: %{id: c.id, name: c.name, country_code: c.country_code}
      )
    end
  end

  defmodule Countries do
    @moduledoc false
    @behaviour Bilimbi.Base.Grid.Source

    import Ecto.Query

    @impl true
    def query(_scope) do
      from(c in "grid_test_countries",
        select: %{code: c.code, name: c.name, population: c.population}
      )
    end
  end

  defmodule Lines do
    @moduledoc false
    @behaviour Bilimbi.Base.Grid.Source

    import Ecto.Query

    @impl true
    def query(_scope) do
      from(l in "grid_test_lines",
        select: %{
          id: l.id,
          order_id: l.order_id,
          sku: l.sku,
          qty: l.qty,
          price: l.price,
          created_at: l.created_at
        }
      )
    end
  end

  defmodule Tags do
    @moduledoc false
    @behaviour Bilimbi.Base.Grid.Source

    import Ecto.Query

    @impl true
    def query(_scope) do
      from(t in "grid_test_tags", select: %{id: t.id, name: t.name})
    end
  end

  defmodule Metrics do
    @moduledoc false
    @behaviour Bilimbi.Base.Grid.Source

    import Ecto.Query

    @columns [:order_id | Enum.map(1..60, &:"m#{&1}")]

    @impl true
    def query(_scope) do
      from(m in "grid_test_metrics", select: map(m, ^@columns))
    end

    def columns, do: @columns
  end

  defmodule Edges do
    @moduledoc false
    import Ecto.Query

    def order_tags(_scope) do
      from(ot in "grid_test_order_tags", select: %{from_key: ot.order_id, to_key: ot.tag_id})
    end
  end

  defmodule NotASource do
    @moduledoc false
    def query(_scope), do: nil
  end

  defmodule ReadsDatabase do
    @moduledoc """
    A source that reads the database while it builds its query, as a table
    bounded by another module's facts does. The table it reads is never
    created, which is the state of every table before the first migration.
    """
    @behaviour Bilimbi.Base.Grid.Source

    import Ecto.Query

    alias Bilimbi.Base.Repo

    @impl true
    def query(_scope) do
      ids = Repo.all(from(b in "grid_test_never_migrated", select: b.owner_id))
      from(o in "grid_test_orders", where: o.id in ^ids, select: %{id: o.id, label: o.label})
    end
  end

  @doc "The `:grid` payload declaring the test domain."
  def tables do
    %{
      tables: [
        %{
          id: "orders",
          label: "Orders",
          capability: "admin.test.order.view",
          source: Orders,
          key: "id",
          label_field: "label",
          time_field: "placed_at",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "label", label: "Label", type: :string},
            %{id: "amount", label: "Amount", type: :decimal},
            %{id: "status", label: "Status", type: :enum, values: ["open", "paid", "void"]},
            %{id: "placed_at", label: "Placed", type: :datetime},
            %{id: "customer_id", type: :integer, hidden: true}
          ],
          links: [
            %{
              id: "customer",
              label: "Customer",
              to: "customers",
              kind: :one,
              on: {"customer_id", "id"}
            },
            %{id: "lines", label: "Lines", to: "lines", kind: :many, on: {"id", "order_id"}},
            %{id: "tags", label: "Tags", to: "tags", kind: :many, via: {Edges, :order_tags}}
          ]
        },
        %{
          id: "customers",
          label: "Customers",
          capability: "admin.test.customer.view",
          source: Customers,
          key: "id",
          label_field: "name",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "name", label: "Name", type: :string},
            %{id: "country_code", label: "Country code", type: :string, hidden: true}
          ],
          links: [
            %{
              id: "country",
              label: "Country",
              to: "countries",
              kind: :one,
              on: {"country_code", "code"}
            },
            %{id: "orders", label: "Orders", to: "orders", kind: :many, on: {"id", "customer_id"}}
          ]
        },
        %{
          id: "countries",
          label: "Countries",
          capability: "admin.test.country.view",
          source: Countries,
          key: "code",
          label_field: "name",
          fields: [
            %{id: "code", label: "Code", type: :string},
            %{id: "name", label: "Name", type: :string},
            %{id: "population", label: "Population", type: :integer}
          ]
        },
        %{
          id: "lines",
          label: "Lines",
          capability: "admin.test.line.view",
          source: Lines,
          key: "id",
          label_field: "sku",
          time_field: "created_at",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "order_id", type: :integer, hidden: true},
            %{id: "sku", label: "SKU", type: :string},
            %{id: "qty", label: "Quantity", type: :integer},
            %{id: "price", label: "Price", type: :decimal},
            %{id: "created_at", label: "Created", type: :datetime}
          ],
          links: [
            %{id: "order", label: "Order", to: "orders", kind: :one, on: {"order_id", "id"}}
          ]
        },
        %{
          id: "tags",
          label: "Tags",
          capability: "admin.test.tag.view",
          source: Tags,
          key: "id",
          label_field: "name",
          fields: [
            %{id: "id", label: "ID", type: :integer},
            %{id: "name", label: "Name", type: :string}
          ]
        },
        # Sixty numeric measures per order, one row each: a wide one-link so a
        # grid can hold a hundred columns for the performance run.
        %{
          id: "metrics",
          label: "Metrics",
          capability: "admin.test.order.view",
          source: Metrics,
          key: "order_id",
          fields: [
            %{id: "order_id", type: :integer, hidden: true}
            | Enum.map(1..60, &%{id: "m#{&1}", label: "Measure #{&1}", type: :integer})
          ],
          links: [
            %{
              id: "metrics",
              label: "Metrics",
              from: "orders",
              to: "metrics",
              kind: :one,
              on: {"id", "order_id"}
            }
          ]
        }
      ]
    }
  end

  @doc "Every capability the test domain declares."
  def capabilities do
    ~w(admin.test.order.view admin.test.customer.view admin.test.country.view admin.test.line.view admin.test.tag.view)
  end

  # Kept so the module's own `import Ecto.Query` is used and the file mirrors a source.
  @doc false
  def all_orders, do: from(o in "grid_test_orders", select: o.id)
end
