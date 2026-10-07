defmodule Bilimbi.Base.Authz.Restricted do
  @moduledoc """
  The value a field reads as when the reader may not see it.

  `Bilimbi.Base.Authz.redact/3` puts this struct in place of a field an
  operator restricted to roles the scope's actor does not hold, so a read
  model never carries a value its reader may not have. The field is not
  dropped and not blanked: an absent field would read as "this record has
  none", and a blank one as "this record's value is empty". Both teach the
  reader something false. This value says what is true: there is a value, and
  this account may not see it. `table_id` and `field_id` name the restriction
  (`Bilimbi.Base.Authz.list_field_restrictions/1`), and `roles` the names of
  the roles that still see it, so the page can tell the person what to ask
  their administrator for.

  A template renders it with `<.restricted>` from
  `Bilimbi.Base.UI.Components`, which is the one designed treatment: the
  word "Restricted", a lock, and the reason in its tooltip. Interpolated
  directly, as `{@value}` or inside an attribute, it renders the word
  "Restricted" through `Phoenix.HTML.Safe`, so a template that was not
  written for it still cannot show the value. It has no `String.Chars`
  implementation on purpose: code that would compare, search or store it as a
  string raises instead of treating the marker as data.
  """

  @enforce_keys [:table_id, :field_id]
  defstruct [:table_id, :field_id, roles: []]

  @type t :: %__MODULE__{table_id: String.t(), field_id: String.t(), roles: [String.t()]}

  @doc "Whether `value` is a restricted field rather than its value."
  @spec restricted?(term()) :: boolean()
  def restricted?(%__MODULE__{}), do: true
  def restricted?(_value), do: false

  @doc "The word a restricted field reads as wherever it is rendered as text."
  @spec text() :: String.t()
  def text, do: "Restricted"

  @doc """
  What to ask an administrator for: the roles that see the field, as the
  `requirement` of `<.restricted>`, or `nil` when no role sees it.
  """
  @spec requirement(t()) :: String.t() | nil
  def requirement(%__MODULE__{roles: []}), do: nil
  def requirement(%__MODULE__{roles: [role]}), do: "the #{role} role"
  def requirement(%__MODULE__{roles: roles}), do: "one of the roles " <> Enum.join(roles, ", ")
end

defimpl Phoenix.HTML.Safe, for: Bilimbi.Base.Authz.Restricted do
  def to_iodata(%Bilimbi.Base.Authz.Restricted{}), do: Bilimbi.Base.Authz.Restricted.text()
end
