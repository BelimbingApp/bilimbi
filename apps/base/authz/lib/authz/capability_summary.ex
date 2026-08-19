defmodule Bilimbi.Base.Authz.CapabilitySummary do
  @moduledoc "Stable read model for a registered capability entry in the catalog."

  @enforce_keys [:id, :key, :domain, :resource, :action, :module]
  defstruct [:id, :key, :domain, :resource, :action, :module]

  @type t :: %__MODULE__{
          id: String.t(),
          key: String.t(),
          domain: String.t(),
          resource: String.t(),
          action: String.t(),
          module: String.t()
        }
end
