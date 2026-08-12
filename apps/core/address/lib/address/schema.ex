defmodule Bilimbi.Core.Address.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "addresses" do
    field :tenant_id, :id
    field :label, :string
    field :phone, :string
    field :line1, :string
    field :line2, :string
    field :line3, :string
    field :locality, :string
    field :postcode, :string
    field :country_iso, :string
    field :admin1_code, :string, source: :admin1Code
    field :raw_input, :string, source: :rawInput
    field :source, :string
    field :source_ref, :string, source: :sourceRef
    field :parser_version, :string, source: :parserVersion
    field :parse_confidence, :decimal, source: :parseConfidence
    field :parsed_at, :naive_datetime
    field :normalized_at, :naive_datetime
    field :normalization_notes, Bilimbi.Base.Database.Json
    field :verification_status, :string, source: :verificationStatus, default: "unverified"
    field :metadata, Bilimbi.Base.Database.Json
    timestamps(type: :naive_datetime, inserted_at: :created_at)
    field :deleted_at, :naive_datetime
  end

  @fields [
    :label,
    :phone,
    :line1,
    :line2,
    :line3,
    :locality,
    :postcode,
    :country_iso,
    :admin1_code,
    :raw_input,
    :source,
    :source_ref,
    :parser_version,
    :parse_confidence,
    :parsed_at,
    :normalized_at,
    :normalization_notes,
    :verification_status,
    :metadata
  ]

  @spec creation_changeset(pos_integer(), map()) :: Ecto.Changeset.t()
  def creation_changeset(tenant_id, attributes) do
    %__MODULE__{}
    |> cast(attributes, @fields)
    |> put_change(:tenant_id, tenant_id)
    |> validate()
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = address, attributes) do
    address
    |> cast(attributes, @fields)
    |> validate()
  end

  @type t :: %__MODULE__{}

  defp validate(changeset) do
    changeset
    |> validate_length(:label, max: 255)
    |> validate_length(:phone, max: 255)
    |> validate_length(:locality, max: 255)
    |> validate_length(:postcode, max: 255)
    |> validate_length(:country_iso, max: 2)
    |> validate_length(:admin1_code, max: 20)
    |> validate_length(:source, max: 255)
    |> validate_length(:source_ref, max: 255)
    |> validate_length(:parser_version, max: 255)
    |> validate_length(:verification_status, max: 255)
    |> foreign_key_constraint(:tenant_id, name: :addresses_tenant_foreign)
    |> foreign_key_constraint(:country_iso, name: :addresses_country_iso_foreign)
    |> foreign_key_constraint(:admin1_code, name: :addresses_admin1code_foreign)
  end
end
