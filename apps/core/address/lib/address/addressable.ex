defmodule Bilimbi.Core.Address.Addressable do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "addressables" do
    field :address_id, :id
    field :addressable_type, :string
    field :addressable_id, :id
    field :is_primary, :boolean, default: false
    field :priority, :integer, default: 0
    field :valid_from, :date
    field :valid_to, :date
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @spec company_changeset(pos_integer(), pos_integer(), String.t(), map()) :: Ecto.Changeset.t()
  def company_changeset(address_id, company_id, company_type, attributes) do
    %__MODULE__{}
    |> cast(attributes, [:is_primary, :priority, :valid_from, :valid_to])
    |> put_change(:address_id, address_id)
    |> put_change(:addressable_type, company_type)
    |> put_change(:addressable_id, company_id)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 32_767)
    |> validate_date_range()
    |> foreign_key_constraint(:address_id, name: :addressables_address_id_foreign)
  end

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
