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

  A field the reader may not see (`withheld` on the mutation, set by
  `Bilimbi.Base.Audit` from the owning module's field policy) is still a row,
  so the reader knows the record changed, but it carries no values: its row
  has `withheld: true` and both sides `:absent`, and a surface renders
  `<.restricted>` in their place. That is different from a sensitive key,
  whose value capture itself redacted.

  Keys are classified as sensitive by the same substring rule both surfaces
  already applied; which fields are redacted at capture is
  `Bilimbi.Base.Audit.MutationCapture`'s decision, not this module's.
  """

  use Phoenix.Component

  import Bilimbi.Base.UI.Components, only: [datetime: 1]

  @typedoc "One side of a field's change."
  @type value :: :absent | {:instant, DateTime.t()} | {:text, String.t()}

  @typedoc "One changed field."
  @type row :: %{
          field: String.t(),
          old: value(),
          new: value(),
          sensitive: boolean(),
          withheld: boolean()
        }

  @sensitive_fragments ["password", "secret", "token", "key", "hash"]

  @doc """
  The changed fields of a mutation, sorted by field name.

  A create lists every recorded attribute against `:absent`, a delete the
  reverse, and an update only the fields whose stored old and new values
  differ.
  """
  @spec rows(map()) :: [row()]
  def rows(mutation) do
    withheld = for field <- Map.get(mutation, :withheld, []), do: withheld_row(field)

    (data_rows(mutation) ++ withheld) |> Enum.sort_by(& &1.field)
  end

  defp data_rows(%{event: "created", new_values: new_values}) when is_map(new_values) do
    new_values
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> row(key, :absent, value(value)) end)
  end

  defp data_rows(%{event: "deleted", old_values: old_values}) when is_map(old_values) do
    old_values
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> row(key, value(value), :absent) end)
  end

  defp data_rows(%{old_values: old_values, new_values: new_values}) do
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

  defp data_rows(_mutation), do: []

  @doc """
  The names of the fields `rows/1` would render, without their values.

  The mutations table uses this for the collapsed row. Building the rows
  walks every value, including large JSON, which the closed row does not show.
  """
  @spec changed_fields(map()) :: [String.t()]
  def changed_fields(mutation) do
    (data_fields(mutation) ++ Enum.map(Map.get(mutation, :withheld, []), &to_string/1))
    |> Enum.sort()
  end

  defp data_fields(%{event: "created", new_values: new_values}) when is_map(new_values) do
    names(Map.keys(new_values))
  end

  defp data_fields(%{event: "deleted", old_values: old_values}) when is_map(old_values) do
    names(Map.keys(old_values))
  end

  defp data_fields(%{old_values: old_values, new_values: new_values}) do
    old_map = if is_map(old_values), do: old_values, else: %{}
    new_map = if is_map(new_values), do: new_values, else: %{}

    (Map.keys(old_map) ++ Map.keys(new_map))
    |> Enum.uniq()
    |> Enum.filter(&(Map.get(old_map, &1) != Map.get(new_map, &1)))
    |> names()
  end

  defp data_fields(_mutation), do: []

  @doc """
  Like `summary/1` but takes a precomputed field list so callers that already
  called `changed_fields/1` avoid a second enumeration of the mutation keys.
  """
  @spec summary_from_fields([String.t()]) :: String.t()
  def summary_from_fields([]), do: "No field changes recorded."
  def summary_from_fields([field]), do: field
  def summary_from_fields(fields), do: field_summary(fields)

  @doc """
  One line naming the changed fields, without their values.

  At most four names are written out. A longer change says how many more
  there are, so a row with a large payload stays one short line.
  """
  @spec summary(map()) :: String.t()
  def summary(mutation) do
    case changed_fields(mutation) do
      [] -> "No field changes recorded."
      [field] -> field
      fields -> field_summary(fields)
    end
  end

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

  The instant includes seconds. Two edits in one minute must stay
  distinguishable; minute precision hides the later one.
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
    %{field: to_string(key), old: old, new: new, sensitive: sensitive_key?(key), withheld: false}
  end

  defp withheld_row(field) do
    %{field: to_string(field), old: :absent, new: :absent, sensitive: false, withheld: true}
  end

  defp names(keys) do
    keys |> Enum.map(&to_string/1) |> Enum.sort()
  end

  defp field_summary(fields) do
    {shown, rest} = Enum.split(fields, 4)
    label = Enum.join(shown, ", ")

    if rest == [] do
      "#{length(fields)} fields: #{label}"
    else
      "#{length(fields)} fields: #{label}, +#{length(rest)}"
    end
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
