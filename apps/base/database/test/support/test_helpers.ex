defmodule Bilimbi.Base.Database.TestHelpers do
  @moduledoc """
  Helpers many data tests would otherwise paste into their own file. Opt in
  with `import Bilimbi.Base.Database.TestHelpers`; `DataCase` does not import
  it, so a test that already defines its own `errors_on/1` still compiles.
  """

  @doc """
  A changeset's errors as `%{field => [message]}` with `%{count}`-style
  placeholders interpolated.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Hides a value's type from the compiler's type checker, so a test can pass
  the wrong type on purpose without a compile-time warning.
  """
  def opaque(value), do: :erlang.element(1, {value})
end
