defmodule Bilimbi.Base.Locale.Resolved do
  @moduledoc "The canonical regional locale and provenance selected for one explicit scope."

  @enforce_keys [:locale, :language, :source]
  defstruct [:locale, :language, :source, :inferred_country]

  @type source :: String.t()
  @type t :: %__MODULE__{
          locale: String.t(),
          language: String.t(),
          source: source(),
          inferred_country: String.t() | nil
        }
end
