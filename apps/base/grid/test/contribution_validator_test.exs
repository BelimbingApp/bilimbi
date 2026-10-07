defmodule Bilimbi.Base.Grid.ContributionValidatorTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Grid.ContributionValidator
  alias Bilimbi.Base.Grid.Link
  alias Bilimbi.Base.Grid.Table
  alias Bilimbi.Base.Grid.TestFixtures
  alias Bilimbi.Base.Grid.TestSources

  defp validate(payload), do: ContributionValidator.validate_contributions!([entry(payload)])
  defp entry(payload), do: %{descriptor: TestFixtures.descriptor(), payload: payload}

  defp orders_only(overrides \\ %{}) do
    [orders | _rest] = TestSources.tables().tables
    %{tables: [Map.merge(orders, overrides) |> Map.put(:links, [])]}
  end

  test "a field's protected flag must be a boolean" do
    assert_raise ArgumentError, ~r/field amount protected must be a boolean/, fn ->
      validate(orders_only(%{fields: mark_field("amount", protected: "yes")}))
    end

    %{tables: %{"orders" => orders}} =
      validate(orders_only(%{fields: mark_field("amount", protected: true)}))

    assert orders.fields["amount"].protected
    refute orders.fields["label"].protected
  end

  test "record types are distinct strings claimed by one table" do
    assert_raise ArgumentError,
                 ~r/table orders record_types must be distinct non-empty strings/,
                 fn ->
                   validate(orders_only(%{record_types: ["Test.Order", "Test.Order"]}))
                 end

    %{tables: %{"orders" => orders}} = validate(orders_only(%{record_types: ["Test.Order"]}))
    assert orders.record_types == ["Test.Order"]

    %{tables: [orders, customers | rest]} = TestSources.tables()

    assert_raise ArgumentError,
                 ~r/record types must belong to one table: Test.Order claimed by/,
                 fn ->
                   validate(%{
                     tables: [
                       Map.put(orders, :record_types, ["Test.Order"]),
                       Map.put(customers, :record_types, ["Test.Order"]) | rest
                     ]
                   })
                 end
  end

  defp mark_field(field_id, attrs) do
    [orders | _rest] = TestSources.tables().tables

    Enum.map(orders.fields, fn
      %{id: ^field_id} = field -> Map.merge(field, Map.new(attrs))
      field -> field
    end)
  end

  test "an empty contribution set is an empty catalog" do
    assert ContributionValidator.validate_contributions!([]) == %{tables: %{}}
  end

  test "the test domain validates into tables carrying their links" do
    %{tables: tables} = validate(TestSources.tables())

    assert Map.keys(tables) |> Enum.sort() == ~w(countries customers lines metrics orders tags)

    assert %Table{owner: "base/grid", key: "id", time_field: "placed_at"} =
             orders = tables["orders"]

    assert Enum.map(Table.links(orders), & &1.id) == ~w(customer lines tags metrics)
    assert %Link{kind: :many, via: {TestSources.Edges, :order_tags}} = orders.links["tags"]
    assert Enum.map(Table.visible_fields(orders), & &1.id) == ~w(id label amount status placed_at)
  end

  test "a link declared from another module's table lands on that table" do
    %{tables: [orders, customers | rest]} = TestSources.tables()

    customers =
      Map.update!(customers, :links, &Enum.reject(&1, fn link -> link.id == "orders" end))

    lines_with_inbound =
      Enum.map(rest, fn
        %{id: "lines"} = lines ->
          Map.update!(
            lines,
            :links,
            &(&1 ++
                [
                  %{
                    id: "placed",
                    from: "customers",
                    to: "orders",
                    kind: :many,
                    on: {"id", "customer_id"}
                  }
                ])
          )

        other ->
          other
      end)

    %{tables: tables} = validate(%{tables: [orders, customers | lines_with_inbound]})

    assert %Link{from: "customers", to: "orders", kind: :many} =
             tables["customers"].links["placed"]
  end

  test "the payload must be a map of tables" do
    assert_raise ArgumentError, ~r/must be %\{tables: \[table maps\]\}/, fn ->
      validate(%{widgets: []})
    end

    assert_raise ArgumentError, ~r/must be %\{tables: \[table maps\]\}/, fn -> validate([]) end
  end

  test "table ids are unique across every contribution" do
    payload = TestSources.tables()

    assert_raise ArgumentError,
                 ~r/duplicate grid table ids: orders declared by base\/grid, base\/grid/,
                 fn ->
                   ContributionValidator.validate_contributions!([
                     entry(payload),
                     entry(orders_only())
                   ])
                 end
  end

  test "a source must implement the Source behaviour and belong to the declaring module" do
    assert_raise ArgumentError, ~r/does not implement Bilimbi.Base.Grid.Source/, fn ->
      validate(orders_only(%{source: TestSources.NotASource}))
    end

    assert_raise ArgumentError, ~r/could not be loaded/, fn ->
      validate(orders_only(%{source: Bilimbi.Base.Grid.NoSuchSource}))
    end

    assert_raise ArgumentError, ~r/does not belong to :bilimbi_base_settings/, fn ->
      ContributionValidator.validate_contributions!([
        %{
          descriptor: %{id: "base/settings", otp_app: :bilimbi_base_settings},
          payload: orders_only()
        }
      ])
    end
  end

  test "validating builds no source query, so a field's column waits for a real scope" do
    %{tables: %{"orders" => orders}} = validate(orders_only())

    assert orders.fields["placed_at"].column == nil

    [declared] = orders_only().tables
    fields = declared.fields ++ [%{id: "title", type: :string, column: :label}]
    %{tables: %{"orders" => orders}} = validate(orders_only(%{fields: fields}))

    assert orders.fields["title"].column == :label
  end

  test "a link names two declared tables and joins on declared fields" do
    assert_raise ArgumentError, ~r/names table "nowhere", which no module declares/, fn ->
      validate(%{
        tables: [
          orders_with_link(%{id: "x", to: "nowhere", kind: :one, on: {"customer_id", "id"}})
        ]
      })
    end

    assert_raise ArgumentError, ~r/joins on orders.nope, which is not declared/, fn ->
      validate(%{
        tables: [
          orders_with_link(%{id: "x", to: "customers", kind: :one, on: {"nope", "id"}}),
          customers_only()
        ]
      })
    end
  end

  test "a :one link joins on the target's key, so a walk cannot multiply rows" do
    assert_raise ArgumentError,
                 ~r/is :one but joins on customers.name rather than its key id/,
                 fn ->
                   validate(%{
                     tables: [
                       orders_with_link(%{
                         id: "x",
                         to: "customers",
                         kind: :one,
                         on: {"customer_id", "name"}
                       }),
                       customers_only()
                     ]
                   })
                 end
  end

  test "a link id cannot shadow a field id or repeat" do
    assert_raise ArgumentError, ~r/has the same id as a field/, fn ->
      validate(%{
        tables: [
          orders_with_link(%{
            id: "label",
            to: "customers",
            kind: :one,
            on: {"customer_id", "id"}
          }),
          customers_only()
        ]
      })
    end
  end

  test "a table declares fields with known types, a key among them, and a dated time field" do
    assert_raise ArgumentError, ~r/declares no fields/, fn ->
      validate(orders_only(%{fields: []}))
    end

    assert_raise ArgumentError, ~r/key "nope" is not a declared field/, fn ->
      validate(orders_only(%{key: "nope"}))
    end

    assert_raise ArgumentError, ~r/time_field must be a date or datetime field/, fn ->
      validate(orders_only(%{time_field: "label"}))
    end

    assert_raise ArgumentError, ~r/has type :money/, fn ->
      validate(orders_only(%{fields: [%{id: "id", type: :money}]}))
    end

    assert_raise ArgumentError, ~r/enum field status needs a non-empty list/, fn ->
      validate(
        orders_only(%{fields: [%{id: "id", type: :integer}, %{id: "status", type: :enum}]})
      )
    end

    assert_raise ArgumentError, ~r/unknown keys \[:colour\]/, fn ->
      validate(orders_only(%{fields: [%{id: "id", type: :integer, colour: "red"}]}))
    end
  end

  defp orders_with_link(link) do
    [orders | _rest] = TestSources.tables().tables
    Map.put(orders, :links, [link])
  end

  defp customers_only do
    [_orders, customers | _rest] = TestSources.tables().tables
    Map.put(customers, :links, [])
  end
end
