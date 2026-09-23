defmodule Bilimbi.Base.Audit.Web.MutationDiff do
  @moduledoc """
  The field-level rows of one mutation's old and new values, shared by the
  record history panel and the mutations page so a diff reads the same on
  both.

  A value that denotes an instant is recognised by its shape, never by its
  field name. Capture writes `NaiveDateTime` and `DateTime` values as ISO
  8601 strings — a naive one is UTC by platform convention, exactly as
  `<.datetime>` reads a `NaiveDateTime` — and Belimbing's serializer wrote
  the same shape into rows Bilimbi adopts. `created_at` and `updated_at`
  are the usual ones, but any timestamp column lands in a diff the same way,
  so the rule is "this string parses as a date-time", and such a value
  renders through `<.datetime>`, where the page's clock choice covers it
  like every other time on the page. It shows seconds, so two changes inside
  one minute read as two different values. A calendar date or a bare time stays
  text: neither denotes an instant, so neither has a zone to shift.

  Keys are classified as sensitive by the same substring rule both surfaces
  already applied; which fields are redacted at capture is
  `Bilimbi.Base.Audit.MutationCapture`'s decision, not this module's.
  """

  use Phoenix.Component

  import Bilimbi.Base.UI.Components, only: [datetime: 1]

  @typedoc "One side of a field's change."
  @type value :: :absent | {:instant, DateTime.t()} | {:text, String.t()}

  @typedoc "One changed field."
  @type row :: %{field: String.t(), old: value(), new: value(), sensitive: boolean()}

  @sensitive_fragments ["password", "secret", "token", "key", "hash"]

  @doc """
  The changed fields of a mutation, sorted by field name.

  A create lists every recorded attribute against `:absent`, a delete the
  reverse, and an update only the fields whose stored old and new values
  differ.
  """
  @spec rows(map()) :: [row()]
  def rows(%{event: "created", new_values: new_values}) when is_map(new_values) do
    new_values
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> row(key, :absent, value(value)) end)
  end

  def rows(%{event: "deleted", old_values: old_values}) when is_map(old_values) do
    old_values
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> row(key, value(value), :absent) end)
  end

  def rows(%{old_values: old_values, new_values: new_values}) do
    old_map = if is_map(old_values), do: old_values, else: %{}
    new_map = if is_map(new_values), do: new_values, else: %{}

    (Map.keys(old_map) ++ Map.keys(new_map))
    |> Enum.uniq()
    |> Enum.sort_by(&to_string/1)
    |> Enum.filter(&(Map.get(old_map, &1) != Map.get(new_map, &1)))
    |> Enum.map(fn key ->
      row(key, value(Map.get(old_map, key)), value(Map.get(new_map, key)))
    end)
  end

  def rows(_mutation), do: []

  @doc "Classifies one stored value for rendering."
  @spec value(term()) :: value()
  def value(nil), do: :absent
  def value(value) when is_binary(value), do: instant(value) || {:text, value}
  def value(value) when is_boolean(value) or is_number(value), do: {:text, to_string(value)}

  def value(value) when is_map(value) or is_list(value) do
    case Jason.encode(value) do
      {:ok, json} -> {:text, json}
      _error -> {:text, inspect(value)}
    end
  end

  def value(value), do: {:text, inspect(value)}

  @doc "Whether a field's values are hidden from the reader."
  @spec sensitive_key?(term()) :: boolean()
  def sensitive_key?(key) do
    key |> to_string() |> String.downcase() |> String.contains?(@sensitive_fragments)
  end

  attr(:id, :string, required: true)
  attr(:value, :any, required: true, doc: "a `t:value/0`")
  attr(:absent, :string, default: "—", doc: "the text standing for `:absent`")
  attr(:class, :any, default: nil)

  @doc """
  Renders one side of a change: an instant through `<.datetime>`, so it
  follows the page's clock, and anything else as its text.
  """
  def diff_value(assigns) do
    ~H"""
    <%= case @value do %>
      <% {:instant, instant} -> %>
        <.datetime id={@id} value={instant} precision={:second} class={@class} />
      <% {:text, text} -> %>
        <span id={@id} class={@class}>{text}</span>
      <% :absent -> %>
        <span id={@id} class={@class}>{@absent}</span>
    <% end %>
    """
  end

  defp row(key, old, new) do
    %{field: to_string(key), old: old, new: new, sensitive: sensitive_key?(key)}
  end

  # A string with an offset is an instant outright; one without is the
  # platform's stored UTC. A date alone or a time alone parses as neither.
  defp instant(string) do
    case DateTime.from_iso8601(string) do
      {:ok, instant, _offset} ->
        {:instant, instant}

      {:error, _reason} ->
        case NaiveDateTime.from_iso8601(string) do
          {:ok, naive} -> {:instant, DateTime.from_naive!(naive, "Etc/UTC")}
          {:error, _reason} -> nil
        end
    end
  end
end
