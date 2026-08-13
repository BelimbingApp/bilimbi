defmodule Bilimbi.Core.Address.LinkedOwner do
  @moduledoc "Stable read model for a live business owner linked to an address."

  @enforce_keys [
    :attachment_id,
    :owner_type,
    :owner_id,
    :name,
    :kind,
    :is_primary,
    :priority
  ]
  defstruct [
    :attachment_id,
    :owner_type,
    :owner_id,
    :name,
    :kind,
    :is_primary,
    :priority,
    :valid_from,
    :valid_to
  ]

  @type owner_type :: :company | :employee

  @type t :: %__MODULE__{
          attachment_id: pos_integer(),
          owner_type: owner_type(),
          owner_id: pos_integer(),
          name: String.t(),
          kind: [String.t()],
          is_primary: boolean(),
          priority: non_neg_integer(),
          valid_from: Date.t() | nil,
          valid_to: Date.t() | nil
        }
end
