defmodule Bilimbi.Base.Locale.Bootstrap do
  @moduledoc """
  Bounded regional facts used for one-time installation-locale inference.

  The higher layer that owns companies and addresses resolves these facts.
  Base Locale neither knows where they came from nor queries higher-layer
  tables. Only `country_iso` and `languages` participate in locale inference;
  the other fields preserve the seam for regional-formatting consumers.
  """

  @enforce_keys [:country_iso]
  defstruct [:country_iso, :country_name, :languages, :currency_code]

  @type t :: %__MODULE__{
          country_iso: String.t(),
          country_name: String.t() | nil,
          languages: String.t() | nil,
          currency_code: String.t() | nil
        }
end
