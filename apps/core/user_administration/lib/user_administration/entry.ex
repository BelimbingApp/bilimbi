defmodule Bilimbi.Core.UserAdministration.Entry do
  @moduledoc """
  One UI-safe User administration entry.

  `company_archived` is true when the account's company is archived or
  soft-deleted: either way the account is read-only and cannot sign in or be
  impersonated. `company_deleted` is true only for a soft-deleted company,
  whose page no longer opens, so the list names it without a link.
  """

  alias Bilimbi.Core.UserAdministration.Role

  @enforce_keys [
    :id,
    :company_id,
    :name,
    :email,
    :created_at,
    :company_name,
    :company_archived,
    :company_deleted,
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
          company_deleted: boolean(),
          roles: [Role.t()]
        }
end
