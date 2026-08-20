defmodule Bilimbi.Core.Geonames.PostcodeOverride do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Bilimbi.Core.Geonames.Postcode

  @primary_key {:id, :id, autogenerate: true}

  @operator_fields [
    :country_iso,
    :postcode,
    :place_name,
    :admin1_code,
    :latitude,
    :longitude,
    :accuracy
  ]

  @materialized_fields [
    :country_iso,
    :postcode,
    :place_name,
    :admin1_code,
    :admin_name1,
    :admin_code1,
    :admin_name2,
    :admin_code2,
    :admin_name3,
    :admin_code3,
    :latitude,
    :longitude,
    :accuracy
  ]

  @source_fields [
    :source_country_iso,
    :source_postcode,
    :source_place_name,
    :source_admin1_code,
    :source_admin_name1,
    :source_admin_code1,
    :source_admin_name2,
    :source_admin_code2,
    :source_admin_name3,
    :source_admin_code3,
    :source_latitude,
    :source_longitude,
    :source_accuracy
  ]

  schema "geonames_postcode_overrides" do
    field(:applied_postcode_id, :integer)

    field(:country_iso, :string)
    field(:postcode, :string)
    field(:place_name, :string)
    field(:admin1_code, :string)
    field(:admin_name1, :string)
    field(:admin_code1, :string)
    field(:admin_name2, :string)
    field(:admin_code2, :string)
    field(:admin_name3, :string)
    field(:admin_code3, :string)
    field(:latitude, :decimal)
    field(:longitude, :decimal)
    field(:accuracy, :integer)

    field(:source_country_iso, :string)
    field(:source_postcode, :string)
    field(:source_place_name, :string)
    field(:source_admin1_code, :string)
    field(:source_admin_name1, :string)
    field(:source_admin_code1, :string)
    field(:source_admin_name2, :string)
    field(:source_admin_code2, :string)
    field(:source_admin_name3, :string)
    field(:source_admin_code3, :string)
    field(:source_latitude, :decimal)
    field(:source_longitude, :decimal)
    field(:source_accuracy, :integer)

    field(:lock_version, :integer, default: 1)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
  end

  @doc false
  def operator_changeset(override, attrs) do
    override
    |> cast(attrs, @operator_fields)
    |> update_change(:country_iso, &(&1 |> String.trim() |> String.upcase()))
    |> update_change(:postcode, &String.trim/1)
    |> update_change(:place_name, &String.trim/1)
    |> update_change(:admin1_code, &normalize_optional/1)
    |> validate_required([:country_iso, :postcode, :place_name])
    |> validate_format(:country_iso, ~r/\A[A-Z]{2}\z/)
    |> validate_length(:postcode, max: 20)
    |> validate_length(:place_name, max: 180)
    |> validate_length(:admin1_code, max: 20)
    |> validate_number(:latitude,
      greater_than_or_equal_to: Decimal.new("-90"),
      less_than_or_equal_to: Decimal.new("90")
    )
    |> validate_number(:longitude,
      greater_than_or_equal_to: Decimal.new("-180"),
      less_than_or_equal_to: Decimal.new("180")
    )
    |> validate_number(:accuracy, greater_than_or_equal_to: 1, less_than_or_equal_to: 6)
    |> validate_coordinate_pair()
  end

  @doc false
  def materialize_changeset(schema, override) do
    schema
    |> Ecto.Changeset.change(Map.take(Map.from_struct(override), @materialized_fields))
  end

  @doc false
  def source_attributes(%Postcode{} = postcode) do
    Map.new(Enum.zip(@materialized_fields, @source_fields), fn {field, source_field} ->
      {source_field, Map.fetch!(postcode, field)}
    end)
  end

  @doc false
  def materialized_fields, do: @materialized_fields

  @doc false
  def source_fields, do: @source_fields

  defp normalize_optional(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.upcase(trimmed)
    end
  end

  defp validate_coordinate_pair(changeset) do
    case {get_field(changeset, :latitude), get_field(changeset, :longitude)} do
      {nil, nil} -> changeset
      {nil, _longitude} -> add_error(changeset, :latitude, "is required when longitude is set")
      {_latitude, nil} -> add_error(changeset, :longitude, "is required when latitude is set")
      {_latitude, _longitude} -> changeset
    end
  end
end
