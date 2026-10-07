defmodule Bilimbi.Base.Grid.Field do
  @moduledoc """
  One field of a catalog table: a value a column can show.

  `column` is the key the owner's source query exposes it under. A field
  that declares none is resolved at boot to the source key its id names
  (`Bilimbi.Base.Grid.ContributionValidator`); until then it is `nil`. `hidden` fields exist for links to join on and never
  appear as columns or suggestions. `values` names the closed set an `:enum`
  field takes, which the band lens colours categorically.

  `capability` is field-level authorization: a field that carries one is in
  the catalog only for an account that holds that key, in addition to the
  table's own. It is the same key the owning module's
  `Bilimbi.Base.Authz.FieldPolicy` names for that column, so a value the
  record page withholds cannot be read as a grid column either. A table's
  key, label and time fields, and the fields a link joins on, take none:
  they are read with the table.
  """

  @types [:integer, :float, :decimal, :string, :boolean, :date, :datetime, :enum]
  @keys [:id, :label, :type, :column, :hidden, :values, :capability]
  @id_pattern ~r/^[a-z][a-z0-9_]*$/

  @enforce_keys [:id, :label, :type, :column]
  defstruct id: nil,
            label: nil,
            type: nil,
            column: nil,
            hidden: false,
            values: nil,
            capability: nil

  @type type :: :integer | :float | :decimal | :string | :boolean | :date | :datetime | :enum

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          type: type(),
          column: atom(),
          hidden: boolean(),
          values: [String.t()] | nil,
          capability: String.t() | nil
        }

  @doc "The field types a contribution may declare."
  @spec types() :: [type()]
  def types, do: @types

  @doc "Whether a value of this type orders on a number line (for bars and heat)."
  @spec numeric?(t() | type()) :: boolean()
  def numeric?(%__MODULE__{type: type}), do: numeric?(type)
  def numeric?(type), do: type in [:integer, :float, :decimal, :date, :datetime]

  @doc false
  @spec new!(map(), String.t()) :: t()
  def new!(attrs, owner) when is_map(attrs) do
    unknown = Map.keys(attrs) -- @keys

    if unknown != [] do
      invalid!(owner, attrs, "unknown keys #{inspect(unknown)}")
    end

    id = fetch_string!(attrs, :id, owner)

    unless Regex.match?(@id_pattern, id) do
      invalid!(owner, attrs, "field id #{inspect(id)} must match #{inspect(@id_pattern)}")
    end

    type = Map.get(attrs, :type)

    unless type in @types do
      invalid!(
        owner,
        attrs,
        "field #{id} has type #{inspect(type)}; expected one of #{inspect(@types)}"
      )
    end

    values = Map.get(attrs, :values)

    if type == :enum and
         not (is_list(values) and values != [] and Enum.all?(values, &is_binary/1)) do
      invalid!(owner, attrs, "enum field #{id} needs a non-empty list of string values")
    end

    if type != :enum and not is_nil(values) do
      invalid!(owner, attrs, "field #{id} is not an enum and takes no values")
    end

    column = Map.get(attrs, :column)

    unless is_atom(column) do
      invalid!(owner, attrs, "field #{id} column must be an atom")
    end

    capability = Map.get(attrs, :capability)

    unless is_nil(capability) or Bilimbi.Base.Authz.CapabilityKey.valid?(capability) do
      invalid!(owner, attrs, "field #{id} capability must be a capability key")
    end

    %__MODULE__{
      id: id,
      label: Map.get(attrs, :label, humanize(id)),
      type: type,
      column: column,
      hidden: Map.get(attrs, :hidden, false) == true,
      values: values,
      capability: capability
    }
  end

  @doc "Whether an account holding `held` may read this field."
  @spec readable?(t(), Enumerable.t()) :: boolean()
  def readable?(%__MODULE__{capability: nil}, _held), do: true
  def readable?(%__MODULE__{capability: capability}, held), do: capability in held

  defp fetch_string!(attrs, key, owner) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> value
      other -> invalid!(owner, attrs, "#{key} must be a non-empty string, got #{inspect(other)}")
    end
  end

  defp humanize(id), do: id |> String.replace("_", " ") |> String.capitalize()

  defp invalid!(owner, attrs, message) do
    raise ArgumentError, "invalid grid field from #{owner} (#{inspect(attrs)}): #{message}"
  end
end
