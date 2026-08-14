defmodule Bilimbi.Base.Settings.Definition do
  @moduledoc "Validated module-owned runtime setting definition."

  alias Bilimbi.Base.Settings.Schema

  @supported_types [:array, :boolean, :float, :integer, :mixed, :string]
  @supported_scopes [:company, :global, :tenant, :user]
  @enforce_keys [:key, :owner, :type, :scopes, :default, :nullable, :encrypted]
  defstruct [
    :key,
    :owner,
    :type,
    :default,
    :label,
    :help,
    :editable,
    :capability,
    scopes: [],
    nullable: false,
    encrypted: false
  ]

  @type t :: %__MODULE__{}

  @spec new!(String.t(), String.t(), map()) :: t()
  def new!(key, owner, attributes) when is_map(attributes) do
    build!(key, owner, attributes)
  rescue
    error in ArgumentError ->
      # Every rejection here names the module that declared the setting. The
      # reader is whoever has to fix it, and a key alone does not tell them
      # which descriptor to open -- keys are namespaced by convention, not by
      # rule. Wrapping once beats threading `owner` through every helper.
      reraise ArgumentError, [message: "#{error.message} (declared by #{owner})"], __STACKTRACE__
  end

  def new!(key, owner, _attributes),
    do: invalid!(key, "must be a map (declared by #{owner})")

  defp build!(key, owner, attributes) do
    type = fetch_atom!(attributes, :type, @supported_types, key)
    scopes = fetch_scopes!(attributes, key)

    unless Map.has_key?(attributes, :default) do
      invalid!(key, "must declare a default")
    end

    definition = %__MODULE__{
      key: key |> non_empty!("definition key") |> within_key_limit!(key),
      owner: non_empty!(owner, "owner"),
      type: type,
      scopes: scopes,
      default: Map.fetch!(attributes, :default),
      nullable: boolean!(Map.get(attributes, :nullable, false), key, :nullable),
      encrypted: boolean!(Map.get(attributes, :encrypted, false), key, :encrypted),
      label: optional_string!(Map.get(attributes, :label), key, :label),
      help: optional_string!(Map.get(attributes, :help), key, :help),
      editable: optional_string!(Map.get(attributes, :editable), key, :editable),
      capability: optional_string!(Map.get(attributes, :capability), key, :capability)
    }

    if definition.editable && (is_nil(definition.label) or is_nil(definition.help)) do
      invalid!(key, "editable definitions must declare label and help")
    end

    unless accepts?(definition, definition.default) do
      invalid!(key, "default is incompatible with #{inspect(type)}")
    end

    definition
  end

  @spec allows_scope?(t(), Bilimbi.Base.Settings.Scope.t() | nil) :: boolean()
  def allows_scope?(%__MODULE__{scopes: scopes}, nil), do: :global in scopes
  def allows_scope?(%__MODULE__{scopes: scopes}, %{type: type}), do: type in scopes

  @spec accepts?(t(), term()) :: boolean()
  def accepts?(%__MODULE__{nullable: nullable}, nil), do: nullable
  def accepts?(%__MODULE__{type: :array}, value), do: is_list(value) or is_map(value)
  def accepts?(%__MODULE__{type: :boolean}, value), do: is_boolean(value)
  def accepts?(%__MODULE__{type: :float}, value), do: is_float(value)
  def accepts?(%__MODULE__{type: :integer}, value), do: is_integer(value)
  def accepts?(%__MODULE__{type: :string}, value), do: is_binary(value)
  def accepts?(%__MODULE__{type: :mixed}, _value), do: true

  @spec matches?(t(), String.t()) :: boolean()
  def matches?(%__MODULE__{key: pattern}, key) do
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*")
    |> then(&Regex.compile!("^#{&1}$"))
    |> Regex.match?(key)
  end

  defp fetch_atom!(attributes, field, supported, key) do
    case Map.fetch(attributes, field) do
      {:ok, value} when is_atom(value) ->
        if value in supported, do: value, else: invalid!(key, "must declare supported #{field}")

      _other ->
        invalid!(key, "must declare supported #{field}")
    end
  end

  defp fetch_scopes!(attributes, key) do
    scopes = Map.get(attributes, :scopes)

    unless is_list(scopes) and scopes != [] and Enum.all?(scopes, &(&1 in @supported_scopes)) and
             length(scopes) == length(Enum.uniq(scopes)) do
      invalid!(key, "must declare unique supported scopes")
    end

    scopes
  end

  defp boolean!(value, _key, _field) when is_boolean(value), do: value
  defp boolean!(_value, key, field), do: invalid!(key, "#{field} must be boolean")
  defp optional_string!(nil, _key, _field), do: nil

  defp optional_string!(value, _key, _field) when is_binary(value) and value != "",
    do: value

  defp optional_string!(_value, key, field), do: invalid!(key, "#{field} must be non-empty")

  # The storage limit, enforced where every other malformed definition is
  # caught. Without this a module can declare an over-long key, have it
  # accepted, appear on a settings screen, and fail only when a user first
  # presses Save -- as far from the cause as the failure can land.
  defp within_key_limit!(value, key) do
    if String.length(value) > Schema.key_max_length() do
      invalid!(key, "key must be at most #{Schema.key_max_length()} characters")
    end

    value
  end

  defp non_empty!(value, _field) when is_binary(value) and value != "", do: value
  defp non_empty!(_value, field), do: raise(ArgumentError, "#{field} must be non-empty")
  defp invalid!(key, reason), do: raise(ArgumentError, "setting #{inspect(key)} #{reason}")
end
