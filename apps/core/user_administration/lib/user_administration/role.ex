defmodule Bilimbi.Core.UserAdministration.Role do
  @moduledoc "One UI-safe Role summary."

  @enforce_keys [:id, :name, :code, :is_system]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: pos_integer(),
          name: binary(),
          code: binary(),
          is_system: boolean()
        }
end
