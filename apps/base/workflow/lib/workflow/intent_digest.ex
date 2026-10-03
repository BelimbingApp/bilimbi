defmodule Bilimbi.Base.Workflow.IntentDigest do
  @moduledoc false
  import Bitwise

  # Belimbing stores one SHA-256 digest per human action request and nothing
  # else about the request's payload (HumanActionService intentHash): PHP
  # json_encode with default flags over the recursively key-sorted intent
  # array. A retained request can only be replayed by reproducing that exact
  # byte string, so every Bilimbi request, legacy or new, uses this one
  # canonical form: byte-ordered object keys, preserved list order, solidus
  # and non-ASCII escaped as PHP does (lowercase hex, UTF-16 surrogates), and
  # an empty map encoded as PHP's empty array `[]`. PHP serializes floats and
  # coerces numeric-string keys in ways this codec cannot reproduce exactly,
  # so both are refused before a request is written rather than hashed wrong.

  @numeric_key ~r/\A[ \t\n\r\x0B\f]*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[ \t\n\r\x0B\f]*\z/

  @type intent :: %{
          subject_type: String.t(),
          subject_id: String.t(),
          actor_type: String.t(),
          actor_id: integer(),
          action_key: String.t(),
          process_run_id: integer() | nil,
          work_item_id: integer() | nil,
          payload: map() | list()
        }

  @spec digest(intent()) :: {:ok, String.t()} | {:error, :unreproducible_intent}
  def digest(intent) do
    with {:ok, json} <- canonical(intent),
         do: {:ok, :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)}
  end

  @doc false
  @spec canonical(intent()) :: {:ok, binary()} | {:error, :unreproducible_intent}
  def canonical(intent) do
    encode(%{
      "subject_type" => intent.subject_type,
      "subject_id" => intent.subject_id,
      "actor_type" => intent.actor_type,
      "actor_id" => intent.actor_id,
      "action_key" => intent.action_key,
      "process_run_id" => intent.process_run_id,
      "work_item_id" => intent.work_item_id,
      "payload" => intent.payload
    })
  end

  @doc false
  @spec encode(term()) :: {:ok, binary()} | {:error, :unreproducible_intent}
  def encode(value) do
    {:ok, value |> term() |> IO.iodata_to_binary()}
  catch
    :unreproducible -> {:error, :unreproducible_intent}
  end

  @spec reproducible?(term()) :: boolean()
  def reproducible?(value), do: match?({:ok, _}, encode(value))

  defp term(nil), do: "null"
  defp term(true), do: "true"
  defp term(false), do: "false"
  defp term(value) when is_integer(value), do: Integer.to_string(value)
  defp term(value) when is_binary(value), do: string(value)

  defp term(value) when is_list(value),
    do: ["[", Enum.intersperse(Enum.map(value, &term/1), ","), "]"]

  defp term(value) when is_map(value) and not is_struct(value) and map_size(value) == 0, do: "[]"

  defp term(value) when is_map(value) and not is_struct(value) do
    pairs =
      value
      |> Enum.map(fn {key, item} -> {key!(key), item} end)
      |> Enum.sort_by(&elem(&1, 0))

    ["{", Enum.intersperse(Enum.map(pairs, fn {k, v} -> [string(k), ":", term(v)] end), ","), "}"]
  end

  defp term(_value), do: throw(:unreproducible)

  defp key!(key) when is_binary(key) do
    if String.valid?(key) and not Regex.match?(@numeric_key, key),
      do: key,
      else: throw(:unreproducible)
  end

  defp key!(_key), do: throw(:unreproducible)

  defp string(value) do
    unless String.valid?(value), do: throw(:unreproducible)
    [?", escape(value), ?"]
  end

  defp escape(<<>>), do: []
  defp escape(<<?", rest::binary>>), do: ["\\\"" | escape(rest)]
  defp escape(<<?\\, rest::binary>>), do: ["\\\\" | escape(rest)]
  defp escape(<<?/, rest::binary>>), do: ["\\/" | escape(rest)]
  defp escape(<<?\b, rest::binary>>), do: ["\\b" | escape(rest)]
  defp escape(<<?\f, rest::binary>>), do: ["\\f" | escape(rest)]
  defp escape(<<?\n, rest::binary>>), do: ["\\n" | escape(rest)]
  defp escape(<<?\r, rest::binary>>), do: ["\\r" | escape(rest)]
  defp escape(<<?\t, rest::binary>>), do: ["\\t" | escape(rest)]
  defp escape(<<char, rest::binary>>) when char < 0x20, do: [unicode(char) | escape(rest)]
  defp escape(<<char, rest::binary>>) when char < 0x80, do: [char | escape(rest)]

  defp escape(<<char::utf8, rest::binary>>) when char < 0x10000,
    do: [unicode(char) | escape(rest)]

  defp escape(<<char::utf8, rest::binary>>) do
    offset = char - 0x10000
    [unicode(0xD800 + (offset >>> 10)), unicode(0xDC00 + (offset &&& 0x3FF)) | escape(rest)]
  end

  defp unicode(char),
    do: ["\\u", char |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")]
end
