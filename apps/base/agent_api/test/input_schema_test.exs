defmodule Bilimbi.Base.AgentApi.InputSchemaTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.AgentApi.InputSchema

  @schema %{
    "type" => "object",
    "required" => ["name"],
    "properties" => %{
      "name" => %{"type" => "string", "maxLength" => 5},
      "count" => %{"type" => "integer", "minimum" => 1, "maximum" => 10},
      "ratio" => %{"type" => "number"},
      "active" => %{"type" => "boolean"},
      "status" => %{"type" => "string", "enum" => ["open", "closed"]},
      "on" => %{"type" => "string", "format" => "date"},
      "at" => %{"type" => "string", "format" => "date-time"},
      "email" => %{"type" => "string", "format" => "email"},
      "tags" => %{"type" => "array", "items" => %{"type" => "string"}},
      "owner" => %{
        "type" => "object",
        "required" => ["id"],
        "properties" => %{"id" => %{"type" => "integer"}}
      }
    }
  }

  test "the schema itself is well formed" do
    assert InputSchema.check_schema(@schema) == :ok
  end

  test "input that matches passes" do
    assert InputSchema.validate(@schema, %{
             "name" => "Ada",
             "count" => 10,
             "ratio" => 0.5,
             "active" => false,
             "status" => "open",
             "on" => "2026-10-11",
             "at" => "2026-10-11T08:00:00Z",
             "email" => "ada@example.com",
             "tags" => ["a", "b"],
             "owner" => %{"id" => 3}
           }) == :ok
  end

  test "each failing field is named by its path with what is wrong" do
    assert {:error, errors} =
             InputSchema.validate(@schema, %{
               "count" => 0,
               "ratio" => "half",
               "status" => "lost",
               "on" => "11/10/2026",
               "at" => "2026-10-11T08:00:00",
               "email" => "nobody",
               "tags" => ["a", 2],
               "owner" => %{},
               "colour" => "red"
             })

    assert errors == %{
             "name" => ["is required"],
             "colour" => ["is not a field of this operation"],
             "count" => ["must be at least 1"],
             "ratio" => ["must be a number"],
             "status" => ["must be one of open, closed"],
             "on" => ["must be a date"],
             "at" => ["must be a date and time with an offset"],
             "email" => ["must be an email address"],
             "tags.1" => ["must be a string"],
             "owner.id" => ["is required"]
           }
  end

  test "an integer is a whole number, and a string respects its length" do
    assert {:error, %{"count" => ["must be an integer"]}} =
             InputSchema.validate(@schema, %{"name" => "Ada", "count" => 2.0})

    assert {:error, %{"name" => ["must be at most 5 characters"]}} =
             InputSchema.validate(@schema, %{"name" => "Adaline"})
  end

  test "input that is not an object, or that uses atom keys, is refused" do
    assert {:error, %{"" => ["must be an object"]}} = InputSchema.validate(@schema, ["Ada"])

    assert {:error, %{"name" => ["is not a field of this operation", "is required"]}} =
             InputSchema.validate(@schema, %{name: "Ada"})
  end
end
