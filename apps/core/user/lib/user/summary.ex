defmodule Bilimbi.Core.User.Summary do
  @moduledoc """
  Stable read model for a user account.

  The credential never leaves the module: `password` and `remember_token` are
  absent by construction, not filtered on the way out.
  """

  @enforce_keys [:id, :name, :email]
  defstruct [:id, :company_id, :employee_id, :name, :email, :email_verified_at]

  @type t :: %__MODULE__{
          id: pos_integer(),
          company_id: pos_integer() | nil,
          employee_id: pos_integer() | nil,
          name: String.t(),
          email: String.t(),
          email_verified_at: NaiveDateTime.t() | nil
        }

  @doc false
  def from_schema(user) do
    %__MODULE__{
      id: user.id,
      company_id: user.company_id,
      employee_id: user.employee_id,
      name: user.name,
      email: user.email,
      email_verified_at: user.email_verified_at
    }
  end
end
