defmodule Bilimbi.Base.Authz.FieldRestriction do
  @moduledoc false

  use Ecto.Schema

  alias Bilimbi.Base.Authz.FieldRestrictionRole

  @timestamps_opts [type: :naive_datetime, inserted_at: :created_at]

  schema "base_authz_field_restrictions" do
    field :tenant_id, :id
    field :table_id, :string
    field :field_id, :string
    has_many :roles, FieldRestrictionRole, foreign_key: :restriction_id
    timestamps()
  end

  @type t :: %__MODULE__{}
end
