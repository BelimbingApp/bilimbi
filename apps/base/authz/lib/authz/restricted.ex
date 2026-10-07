defmodule Bilimbi.Base.Authz.Restricted do
  @moduledoc """
  The value a field reads as when the reader may not see it.

  `Bilimbi.Base.Authz.redact/3` puts this struct in place of a field whose
  capability the scope's actor lacks, so a read model never carries a value
  its reader may not have. The field is not dropped and not blanked: an
  absent field would read as "this record has none", and a blank one as
  "this record's value is empty". Both teach the reader something false.
  This value says what is true: there is a value, and this account may not
  see it. `capability` names what would show it, so the page can tell the
  person which permission to ask their administrator for.

  A template renders it with `<.restricted>` from
  `Bilimbi.Base.UI.Components`, which is the one designed treatment: the
  word "Restricted", a lock, and the reason in its tooltip. Interpolated
  directly, as `{@value}` or inside an attribute, it renders the word
  "Restricted" through `Phoenix.HTML.Safe`, so a template that was not
  written for it still cannot show the value. It has no `String.Chars`
  implementation on purpose: code that would compare, search or store it as a
  string raises instead of treating the marker as data.
  """

  @enforce_keys [:capability]
  defstruct [:capability]

  @type t :: %__MODULE__{capability: String.t()}

  @doc "Whether `value` is a restricted field rather than its value."
  @spec restricted?(term()) :: boolean()
  def restricted?(%__MODULE__{}), do: true
  def restricted?(_value), do: false

  @doc "The word a restricted field reads as wherever it is rendered as text."
  @spec text() :: String.t()
  def text, do: "Restricted"
end

defimpl Phoenix.HTML.Safe, for: Bilimbi.Base.Authz.Restricted do
  def to_iodata(%Bilimbi.Base.Authz.Restricted{}), do: Bilimbi.Base.Authz.Restricted.text()
end
