defmodule Bilimbi.Base.UI.FormErrors do
  @moduledoc """
  Copies a domain changeset's errors onto the schemaless changeset a form renders.

  A form LiveView validates its own schemaless changeset, then hands the
  params to a domain API that has the last word. When that API refuses with a
  changeset, the refusal belongs on the form: `copy/3` adds every error of the
  domain changeset to the form's changeset, so each field the form renders
  shows its own reason.

  A domain changeset can also carry an error on a field the form does not
  render, such as a field the page assigns itself. `:fallback` decides what
  happens to it, and the choice is the page's, made once in the call:

    * `:drop` (the default) discards it. Choose this only when the form can
      never offer a way to correct that field.
    * a field name moves it onto that rendered field, worded
      `"<field> <message>"` so the alert still names its cause.

  Options:

    * `:only` — the fields the form renders, as a list or a map keyed by
      field (a page's `@field_types` works as is). Every other field is a
      fallback case. Omit it when the form renders every field.
    * `:fallback` — `:drop` or a field name, as above.
    * `:action` — the changeset action to set, so the form shows its errors.
      Omit it to leave the action as it is.

  Call it by module, not through an import, as `Bilimbi.Base.UI.Params` is.
  """

  alias Ecto.Changeset

  @type option ::
          {:only, [atom()] | %{optional(atom()) => term()}}
          | {:fallback, :drop | atom()}
          | {:action, atom()}

  @spec copy(Changeset.t(), Changeset.t(), [option()]) :: Changeset.t()
  def copy(%Changeset{} = form_changeset, %Changeset{} = domain_changeset, opts \\ []) do
    rendered = opts |> Keyword.get(:only) |> rendered_fields()
    fallback = Keyword.get(opts, :fallback, :drop)

    copied =
      Enum.reduce(domain_changeset.errors, form_changeset, fn {field, {message, meta}}, acc ->
        cond do
          rendered?(rendered, field) -> Changeset.add_error(acc, field, message, meta)
          fallback == :drop -> acc
          true -> Changeset.add_error(acc, fallback, "#{field} #{message}", meta)
        end
      end)

    case Keyword.fetch(opts, :action) do
      {:ok, action} -> %{copied | action: action}
      :error -> copied
    end
  end

  defp rendered_fields(nil), do: :all
  defp rendered_fields(%{} = fields), do: fields |> Map.keys() |> MapSet.new()
  defp rendered_fields(fields) when is_list(fields), do: MapSet.new(fields)

  defp rendered?(:all, _field), do: true
  defp rendered?(%MapSet{} = fields, field), do: MapSet.member?(fields, field)
end
