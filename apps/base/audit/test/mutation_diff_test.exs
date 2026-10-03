defmodule Bilimbi.Base.Audit.Web.MutationDiffTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.Audit.Web.MutationDiff

  test "summary names the changed fields and leaves their values out" do
    mutation = %{
      event: "updated",
      old_values: %{"name" => "Acme Inc", "city" => "Johor"},
      new_values: %{"name" => "Acme Corp", "city" => "Penang"}
    }

    assert MutationDiff.summary(mutation) == "2 fields: city, name"
    refute MutationDiff.summary(mutation) =~ "Acme"
    assert MutationDiff.changed_fields(mutation) == ["city", "name"]
  end

  test "summary is one field's name, or a capped list" do
    assert MutationDiff.summary(%{event: "created", new_values: %{"name" => "Acme"}}) ==
             "name"

    values = Map.new(1..8, &{"field_#{&1}", String.duplicate("x", 2_000)})
    summary = MutationDiff.summary(%{event: "created", new_values: values})

    assert summary == "8 fields: field_1, field_2, field_3, field_4, +4"
    refute summary =~ "xxxx"
  end

  test "an unchanged update has nothing to open" do
    mutation = %{
      event: "updated",
      old_values: %{"name" => "Acme"},
      new_values: %{"name" => "Acme"}
    }

    assert MutationDiff.changed_fields(mutation) == []
    assert MutationDiff.summary(mutation) == "No field changes recorded."
  end
end
