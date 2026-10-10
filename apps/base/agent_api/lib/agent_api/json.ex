defmodule Bilimbi.Base.AgentApi.Json do
  @moduledoc """
  Makes an operation's result JSON-ready.

  A field the reader may not see arrives as a
  `Bilimbi.Base.Authz.Restricted` marker and leaves as
  `%{"restricted" => true}`: there is a value, and this person may not see
  it. Nothing else about the marker is written out.

  Map keys become strings, and a predicate key loses its `?`
  (`primary?` becomes `"primary"`). Dates and times become ISO 8601
  strings and decimals their exact string. Any other struct is written as
  its fields. A tuple, pid, function or reference is a handler defect and
  raises rather than being guessed at.
  """

  alias Bilimbi.Base.Authz.Restricted

  @doc "The JSON-ready form of `value`."
  @spec encode(term()) :: term()
  def encode(%Restricted{}), do: %{"restricted" => true}
  def encode(%Date{} = date), do: Date.to_iso8601(date)
  def encode(%Time{} = time), do: Time.to_iso8601(time)
  def encode(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  def encode(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def encode(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)

  def encode(%_{} = struct) do
    struct |> Map.from_struct() |> Map.delete(:__meta__) |> encode()
  end

  def encode(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key(key), encode(value)} end)

  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  def encode(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  def encode(nil), do: nil
  def encode(atom) when is_atom(atom), do: Atom.to_string(atom)

  def encode(value) do
    raise ArgumentError, "an agent operation result cannot carry #{inspect(value)}"
  end

  defp key(key) when is_binary(key), do: key
  defp key(key) when is_atom(key), do: key |> Atom.to_string() |> String.trim_trailing("?")

  defp key(key) do
    raise ArgumentError, "an agent operation result cannot use #{inspect(key)} as a key"
  end
end
