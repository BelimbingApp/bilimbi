defmodule Bilimbi.Base.UI.FormErrorsTest do
  @moduledoc """
  How a domain refusal lands on the schemaless changeset a form renders.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.FormErrors

  @types %{name: :string, code: :string}

  defp form, do: Ecto.Changeset.cast({%{}, @types}, %{}, [:name, :code])

  defp domain do
    {%{}, %{name: :string, tenant_id: :integer}}
    |> Ecto.Changeset.cast(%{}, [])
    |> Ecto.Changeset.add_error(:name, "has already been taken", constraint: :unique)
    |> Ecto.Changeset.add_error(:tenant_id, "is invalid")
  end

  defp messages(changeset),
    do: changeset.errors |> Enum.map(fn {f, {m, _}} -> {f, m} end) |> Enum.sort()

  test "copies every error when the form renders every field" do
    copied = FormErrors.copy(form(), domain())

    assert messages(copied) == [name: "has already been taken", tenant_id: "is invalid"]
    assert copied.action == nil
  end

  test "keeps the error metadata so the message still translates" do
    copied = FormErrors.copy(form(), domain())

    assert {"has already been taken", [constraint: :unique]} = copied.errors[:name]
  end

  test "drops an error on a field the form does not render" do
    copied = FormErrors.copy(form(), domain(), only: @types)

    assert messages(copied) == [name: "has already been taken"]
  end

  test "accepts the rendered fields as a list" do
    copied = FormErrors.copy(form(), domain(), only: [:name])

    assert messages(copied) == [name: "has already been taken"]
  end

  test "moves an error on an unrendered field onto the named field, naming its cause" do
    copied = FormErrors.copy(form(), domain(), only: [:name], fallback: :code)

    assert messages(copied) == [code: "tenant_id is invalid", name: "has already been taken"]
  end

  test "sets the action only when asked" do
    assert FormErrors.copy(form(), domain(), action: :insert).action == :insert
    assert FormErrors.copy(form(), domain()).action == nil
  end
end
