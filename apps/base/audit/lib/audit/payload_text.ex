defmodule Bilimbi.Base.Audit.PayloadText do
  @moduledoc """
  The one bound on free text stored in an audit payload.

  Captured mutations and recorded console commands store text as written,
  cut at #{2000} characters with an explicit marker so a reader knows the
  stored value is a prefix. Nothing here redacts by content: redaction is
  by field name, in `Bilimbi.Base.Audit.MutationCapture`.
  """

  @truncate_at 2000

  @doc "The number of characters a stored text keeps before the marker."
  @spec limit() :: pos_integer()
  def limit, do: @truncate_at

  @doc """
  Returns `text` unchanged when it fits, otherwise its first #{2000}
  characters followed by ` [truncated N chars]`, where N is the original
  length.
  """
  @spec bounded(String.t()) :: String.t()
  def bounded(text) when is_binary(text) do
    length = String.length(text)

    if length > @truncate_at do
      String.slice(text, 0, @truncate_at) <> " [truncated #{length} chars]"
    else
      text
    end
  end
end
