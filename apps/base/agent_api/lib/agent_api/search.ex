defmodule Bilimbi.Base.AgentApi.Search do
  @moduledoc """
  Ranks operations and guides by the words an agent typed.

  The ranking is deterministic and in memory over the validated registry:
  no model, no index, no call outside the process. Text is lowercased,
  split on anything that is not a letter or a digit, and each word loses a
  simple plural or `-ing` ending, so "companies" finds "company" and
  "listing" finds "list". A handful of filler words are dropped.

  A word scores once for each place it appears: a key segment 3, the title
  3, a keyword 2, the summary 1, and a guide's body 0.5. An entry's score is
  the sum over the words, an entry that matches no word is left out, and
  ties fall to the key. With no words at all every candidate is returned,
  ordered by key, so an agent can browse what it may use.
  """

  alias Bilimbi.Base.AgentApi.Definition
  alias Bilimbi.Base.AgentApi.Guide

  @stop_words ~w(a an the of for to in on and or by with my me i please)

  @doc "Scores and orders `entries` by `words`, dropping those that match nothing."
  @spec rank([Definition.t() | Guide.t()], String.t()) :: [{Definition.t() | Guide.t(), number()}]
  def rank(entries, words) when is_list(entries) and is_binary(words) do
    case tokens(words) do
      [] ->
        entries |> Enum.sort_by(& &1.key) |> Enum.map(&{&1, 0})

      query ->
        entries
        |> Enum.map(&{&1, score(&1, query)})
        |> Enum.filter(fn {_entry, score} -> score > 0 end)
        |> Enum.sort_by(fn {entry, score} -> {-score, entry.key} end)
    end
  end

  @doc "The words `text` is matched on, normalised as described above."
  @spec tokens(String.t()) :: [String.t()]
  def tokens(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(&(&1 in @stop_words))
    |> Enum.map(&stem/1)
    |> Enum.uniq()
  end

  defp score(entry, query) do
    fields = fields(entry)

    Enum.reduce(query, 0, fn word, total ->
      total +
        Enum.reduce(fields, 0, fn {words, weight}, sum ->
          if MapSet.member?(words, word), do: sum + weight, else: sum
        end)
    end)
  end

  defp fields(entry) do
    [
      {entry.key |> String.split(".") |> Enum.flat_map(&tokens/1) |> MapSet.new(), 3},
      {MapSet.new(tokens(entry.title)), 3},
      {entry.keywords |> Enum.flat_map(&tokens/1) |> MapSet.new(), 2},
      {MapSet.new(tokens(entry.summary)), 1}
    ] ++ body(entry)
  end

  defp body(%Guide{body: body}), do: [{MapSet.new(tokens(body)), 0.5}]
  defp body(%Definition{}), do: []

  defp stem(word) do
    cond do
      String.length(word) > 4 and String.ends_with?(word, "ies") ->
        String.slice(word, 0..-4//1) <> "y"

      String.length(word) > 4 and String.ends_with?(word, ~w(sses uses xes ches shes)) ->
        String.slice(word, 0..-3//1)

      String.length(word) > 5 and String.ends_with?(word, "ing") ->
        String.slice(word, 0..-4//1)

      String.length(word) > 3 and String.ends_with?(word, "s") and
          not String.ends_with?(word, ["ss", "us"]) ->
        String.slice(word, 0..-2//1)

      true ->
        word
    end
  end
end
