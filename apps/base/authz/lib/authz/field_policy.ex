defmodule Bilimbi.Base.Authz.FieldPolicy do
  @moduledoc """
  Which fields of a read model need a capability of their own to be seen.

  Page-level authorization decides whether a record may be opened. A field
  policy decides, field by field, which of its values the reader may see:
  the owning module declares each sensitive field with the capability that
  shows it, and `Bilimbi.Base.Authz.redact/3` replaces every field the
  reader lacks with `Bilimbi.Base.Authz.Withheld`. The policy lives with the
  read model it governs, declared once by the module that owns the table,
  and that one declaration drives its reads, its writes
  (`refuse_changes/2`), and anything else that shows the same column, such
  as the module's grid fields.

  The capability is an ordinary registered key, declared and granted like
  any other. An unknown key withholds the field from everyone, because
  `Bilimbi.Base.Authz` fails closed on a key no module declares.

      @policy FieldPolicy.new!(tax_id: "admin.company.sensitive.view",
                               email: "admin.company.sensitive.view")
  """

  alias Bilimbi.Base.Authz.CapabilityKey

  @enforce_keys [:fields]
  defstruct fields: []

  @type t :: %__MODULE__{fields: [{atom(), String.t()}]}

  @doc """
  Declares the sensitive fields and the capability that shows each.

  Raises on a field that is not an atom, a capability that is not a valid
  key, or a field declared twice: a policy is a module constant, so a defect
  in it is a defect in the module, found when it is built.
  """
  @spec new!(keyword(String.t()) | %{optional(atom()) => String.t()}) :: t()
  def new!(fields) when is_list(fields) or is_map(fields) do
    fields = Enum.to_list(fields)

    Enum.each(fields, fn
      {field, capability} when is_atom(field) and not is_nil(field) ->
        unless CapabilityKey.valid?(capability) do
          raise ArgumentError,
                "field policy for #{inspect(field)} names an invalid capability key " <>
                  inspect(capability)
        end

      other ->
        raise ArgumentError,
              "field policy entries are {field_atom, capability}; got #{inspect(other)}"
    end)

    names = Keyword.keys(fields)

    if Enum.uniq(names) != names do
      raise ArgumentError, "field policy declares a field twice: #{inspect(names)}"
    end

    %__MODULE__{fields: fields}
  end

  @doc "The declared fields, in declaration order."
  @spec fields(t()) :: [atom()]
  def fields(%__MODULE__{fields: fields}), do: Keyword.keys(fields)

  @doc "The distinct capabilities the policy names, in first-seen order."
  @spec capabilities(t()) :: [String.t()]
  def capabilities(%__MODULE__{fields: fields}), do: fields |> Keyword.values() |> Enum.uniq()

  @doc "The capability that shows `field`; raises for a field the policy does not name."
  @spec capability!(t(), atom()) :: String.t()
  def capability!(%__MODULE__{fields: fields}, field) when is_atom(field) do
    case Keyword.fetch(fields, field) do
      {:ok, capability} -> capability
      :error -> raise ArgumentError, "field policy does not name #{inspect(field)}"
    end
  end

  @doc """
  The fields of the policy whose capability is not in `held`, in declaration
  order. `held` is the reader's effective allow list.
  """
  @spec withheld(t(), Enumerable.t()) :: [atom()]
  def withheld(%__MODULE__{fields: fields}, held) do
    held = MapSet.new(held)

    for {field, capability} <- fields, not MapSet.member?(held, capability), do: field
  end

  @doc """
  Refuses a change to any field in `withheld` with an error on that field.

  A value the reader may not see is not theirs to change either: an editor
  cannot show what it would replace, and a write that lands blind is
  indistinguishable from an accident. The owning module calls this on its
  update changeset with the fields `Bilimbi.Base.Authz.withheld_fields/2`
  returned for the same scope, so the API refuses what the page never
  offered. A change that leaves the field as it is, which Ecto already
  drops, is not a change and passes.
  """
  @spec refuse_changes(Ecto.Changeset.t(), [atom()]) :: Ecto.Changeset.t()
  def refuse_changes(%Ecto.Changeset{} = changeset, withheld) when is_list(withheld) do
    Enum.reduce(withheld, changeset, fn field, acc ->
      if Map.has_key?(acc.changes, field) do
        Ecto.Changeset.add_error(
          acc,
          field,
          "is withheld from this account and cannot be changed"
        )
      else
        acc
      end
    end)
  end
end
