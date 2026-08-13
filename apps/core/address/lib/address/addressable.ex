defmodule Bilimbi.Core.Address.Addressable do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @company_kinds ~w(headquarters billing shipping branch other)

  schema "addressables" do
    field(:address_id, :id)
    field(:addressable_type, :string)
    field(:addressable_id, :id)
    field(:kind, Bilimbi.Base.Database.Json, default: [])
    field(:is_primary, :boolean, default: false)
    field(:priority, :integer, default: 0)
    field(:valid_from, :date)
    field(:valid_to, :date)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @type t :: %__MODULE__{}

  @doc false
  @spec company_kinds() :: [String.t()]
  def company_kinds, do: @company_kinds

  @spec company_changeset(pos_integer(), pos_integer(), String.t(), map()) :: Ecto.Changeset.t()
  def company_changeset(address_id, company_id, company_type, attributes) do
    %__MODULE__{}
    |> cast_attachment(attributes)
    |> put_change(:address_id, address_id)
    |> put_change(:addressable_type, company_type)
    |> put_change(:addressable_id, company_id)
    |> validate_attachment()
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = attachment, attributes) do
    attachment
    |> cast_attachment(attributes)
    |> validate_attachment()
  end

  defp cast_attachment(attachment, attributes) do
    cast(attachment, attributes, [:kind, :is_primary, :priority, :valid_from, :valid_to])
  end

  defp validate_attachment(changeset) do
    changeset
    |> validate_change(:kind, &validate_kind/2)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 32_767)
    |> validate_date_range()
    |> foreign_key_constraint(:address_id, name: :addressables_address_id_foreign)
  end

  defp validate_kind(:kind, kinds) when is_list(kinds) do
    if Enum.all?(kinds, &(&1 in @company_kinds)) do
      []
    else
      [kind: "contains an unsupported address kind"]
    end
  end

  defp validate_kind(:kind, _kinds), do: [kind: "must be a list of address kinds"]

  defp validate_date_range(changeset) do
    valid_from = get_field(changeset, :valid_from)
    valid_to = get_field(changeset, :valid_to)

    if valid_from && valid_to && Date.after?(valid_from, valid_to) do
      add_error(changeset, :valid_to, "must be on or after valid_from")
    else
      changeset
    end
  end
end
