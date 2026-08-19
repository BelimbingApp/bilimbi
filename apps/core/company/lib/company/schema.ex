defmodule Bilimbi.Core.Company.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          parent_id: pos_integer() | nil,
          tenant_id: pos_integer() | nil,
          name: String.t() | nil,
          code: String.t() | nil,
          status: String.t() | nil,
          legal_name: String.t() | nil,
          registration_number: String.t() | nil,
          tax_id: String.t() | nil,
          legal_entity_type_id: pos_integer() | nil,
          jurisdiction: String.t() | nil,
          email: String.t() | nil,
          website: String.t() | nil,
          scope_activities: map() | nil,
          metadata: map() | nil,
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil,
          deleted_at: NaiveDateTime.t() | nil
        }

  schema "companies" do
    field(:parent_id, :id)
    field(:tenant_id, :id)
    field(:name, :string)
    field(:code, :string)
    field(:status, :string)
    field(:legal_name, :string)
    field(:registration_number, :string)
    field(:tax_id, :string)
    field(:legal_entity_type_id, :id)
    field(:jurisdiction, :string)
    field(:email, :string)
    field(:website, :string)
    field(:scope_activities, Bilimbi.Base.Database.Json)
    field(:metadata, Bilimbi.Base.Database.Json)
    timestamps(type: :naive_datetime, inserted_at: :created_at)
    field(:deleted_at, :naive_datetime)
  end

  @creation_fields [
    :parent_id,
    :name,
    :code,
    :status,
    :legal_name,
    :registration_number,
    :tax_id,
    :legal_entity_type_id,
    :jurisdiction,
    :email,
    :website,
    :scope_activities,
    :metadata
  ]

  @update_fields @creation_fields
  @statuses ~w(active suspended pending archived)

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @spec creation_changeset(pos_integer(), map()) :: Ecto.Changeset.t()
  def creation_changeset(tenant_id, attributes) do
    %__MODULE__{status: "active"}
    |> cast(attributes, @creation_fields)
    |> put_change(:tenant_id, tenant_id)
    |> update_change(:name, &trim_text/1)
    |> maybe_put_code_from_name()
    |> update_change(:code, &trim_text/1)
    |> validate_required([:tenant_id, :name, :code, :status])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:code, min: 1, max: 255)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must be an email address")
    |> validate_jurisdiction()
    |> unique_constraint(:code, name: :companies_code_unique)
    |> foreign_key_constraint(:tenant_id, name: :companies_tenant_foreign)
    |> foreign_key_constraint(:parent_id, name: :companies_parent_tenant_foreign)
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = company, attributes) do
    company
    |> cast(attributes, @update_fields)
    |> update_change(:name, &trim_text/1)
    |> update_change(:code, &trim_text/1)
    |> validate_required([:name, :code, :status])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:code, min: 1, max: 255)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:legal_name, max: 255)
    |> validate_length(:registration_number, max: 255)
    |> validate_length(:tax_id, max: 255)
    |> validate_length(:jurisdiction, max: 2)
    |> validate_jurisdiction()
    |> validate_length(:email, max: 255)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must be an email address")
    |> validate_length(:website, max: 255)
    |> check_parent_not_self()
    |> unique_constraint(:code, name: :companies_code_unique)
    |> foreign_key_constraint(:parent_id, name: :companies_parent_tenant_foreign)
  end

  defp validate_jurisdiction(changeset) do
    validate_change(changeset, :jurisdiction, fn :jurisdiction, value ->
      case value do
        nil ->
          []

        iso when is_binary(iso) ->
          case Bilimbi.Core.Geonames.get_country(iso) do
            %Bilimbi.Core.Geonames.CountrySummary{} -> []
            nil -> [jurisdiction: "must be a valid country ISO code"]
          end

        _ ->
          [jurisdiction: "is invalid"]
      end
    end)
  end

  # Belimbing `Company::creating` slugs a blank code from the name
  # (`BlbStr::code`). Keep that durable behaviour here, not in the LiveView.
  defp maybe_put_code_from_name(changeset) do
    case blank_text?(get_field(changeset, :code)) do
      true ->
        case slug_code(get_field(changeset, :name)) do
          "" -> changeset
          generated -> put_change(changeset, :code, generated)
        end

      false ->
        changeset
    end
  end

  # Mirrors `BlbStr::code/2`, which is `mb_strtolower(Str::slug($value, "_"))`.
  # Laravel's slug has four steps that a plain "replace anything unwanted with
  # the separator" does not reproduce, and each one changes a real name:
  #
  #   * dashes flip to the separator first        -- "A-B"        -> "a_b"
  #   * "@" expands to the separated word "at"    -- "me@you"     -> "me_at_you"
  #   * remaining punctuation is REMOVED, not     -- "A&B Trading"-> "ab_trading"
  #     turned into a separator                                     (not "a_b_trading")
  #   * the string is transliterated to ASCII     -- "Cafe\u0301 Ltd" -> "cafe_ltd"
  #                                                                 (not "caf_ltd")
  #
  # Transliteration here is NFD plus combining-mark removal, which covers Latin
  # accents; anything still non-ASCII is dropped by the character filter, as
  # `Str::ascii/1` does. A name with no ASCII letters slugs to "", and the
  # caller leaves the code unset so `validate_required/2` reports it.
  defp slug_code(name) when is_binary(name) do
    name
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.replace("-", "_")
    |> String.replace("@", "_at_")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_\s]+/u, "")
    |> String.replace(~r/[_\s]+/u, "_")
    |> String.trim("_")
    |> String.slice(0, 255)
  end

  defp slug_code(_name), do: ""

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value

  defp blank_text?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_text?(nil), do: true
  defp blank_text?(_value), do: false

  defp check_parent_not_self(changeset) do
    case get_change(changeset, :parent_id) do
      nil ->
        changeset

      parent_id ->
        if parent_id == changeset.data.id do
          add_error(changeset, :parent_id, "cannot be set to itself")
        else
          changeset
        end
    end
  end
end
