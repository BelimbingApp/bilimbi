defmodule Bilimbi.Base.Authz.FieldRestrictionSummary do
  @moduledoc """
  Stable read model of one field access restriction: the catalog table and
  field it names, with their labels, and the roles that still see the field.
  """

  @enforce_keys [:id, :table_id, :field_id]
  defstruct [
    :id,
    :table_id,
    :table_label,
    :field_id,
    :field_label,
    :created_at,
    :updated_at,
    role_ids: [],
    role_names: []
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          table_id: String.t(),
          table_label: String.t(),
          field_id: String.t(),
          field_label: String.t(),
          created_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil,
          role_ids: [pos_integer()],
          role_names: [String.t()]
        }
end
