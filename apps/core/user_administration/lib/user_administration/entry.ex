defmodule Bilimbi.Core.UserAdministration.Entry do
  @moduledoc "One UI-safe User administration entry."

  alias Bilimbi.Core.UserAdministration.Role

  @enforce_keys [
    :id,
    :company_id,
    :name,
    :email,
    :created_at,
    :company_name,
    :company_archived,
    :roles
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer(),
          name: binary(),
          email: binary(),
          created_at: NaiveDateTime.t() | nil,
          company_name: binary(),
          company_archived: boolean(),
          roles: [Role.t()]
        }
end
