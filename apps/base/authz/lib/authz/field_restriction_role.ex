defmodule Bilimbi.Base.Authz.FieldRestrictionRole do
  @moduledoc false

  use Ecto.Schema

  alias Bilimbi.Base.Authz.FieldRestriction
  alias Bilimbi.Base.Authz.Role

  @timestamps_opts [type: :naive_datetime, inserted_at: :created_at]

  schema "base_authz_field_restriction_roles" do
    belongs_to :restriction, FieldRestriction
    belongs_to :role, Role
    timestamps()
  end

  @type t :: %__MODULE__{}
end
