defmodule Bilimbi.Base.Settings.Form do
  @moduledoc """
  The field list and save semantics behind a settings screen.

  A screen does not name its fields. It names one or more **groups** — the
  dotted `editable` id a definition declares — and this module turns the
  registry into the fields to render, mirroring Belimbing's
  `app/Base/Settings/Livewire/SettingsForm.php` and its `HandlesSettingsFields`
  concern. A module that declares a new editable setting gets it on screen with
  no UI change, which is the whole point of generating the form.

  Everything here is pure except `load/2` and `save/3`, which read and write
  through `Bilimbi.Base.Settings`. There is no Phoenix dependency: rendering
  belongs to the screen, and the rules below belong to every screen equally.

  ## The three rules that are easy to get wrong

  **Clearing is not writing an empty value.** Submitting a blank field calls
  `Settings.delete/2`, removing this scope's override so the value resolves
  from the next scope out or from the definition's default. Writing `""`
  instead would pin an empty string *as* the override, and the field would look
  cleared while permanently shadowing the value it should have inherited.

  **Inherited is not the same as set here.** `Settings.overridden?/2` is the
  only thing that distinguishes them, and a screen that does not show the
  difference makes clearing a field look like it did nothing — the value comes
  straight back, because it was always inherited.

  **An encrypted value never reaches the browser.** A stored secret renders as
  a mask, and a submission still equal to that mask means "unchanged", not
  "set it to the mask".
  """

  alias Bilimbi.Base.Settings
  alias Bilimbi.Base.Settings.Definition
  alias Bilimbi.Base.Settings.Scope

  @typedoc """
  One rendered field.

  `value` is what to display; `overridden?` says whether it is set at this
  scope or inherited; `source_scope` names where an inherited value came from,
  so a screen can say *why* a field looks the way it does.
  """
  @type field :: %{
          key: String.t(),
          definition: Definition.t(),
          value: term(),
          overridden?: boolean(),
          source_scope: :company | :global | :tenant | :user,
          encrypted?: boolean()
        }

  @doc """
  The mask shown in place of a stored secret.

  Belimbing's `Str::DEFAULT_SAVED_SECRET_MASK`. A submitted value still equal
  to this is a field the user did not touch.
  """
  @spec secret_mask() :: String.t()
  def secret_mask, do: "••••••••"

  @doc """
  Every editable field in `groups`, ordered by group then key.

  Ordering is by group first so a screen can render each group as its own tab
  or section in the order it asked for them, and by key within a group so the
  same registry always produces the same screen.
  """
  @spec fields([String.t()], Scope.t() | nil) :: [field()]
  def fields(groups, scope) when is_list(groups) do
    definitions = Settings.definitions()

    groups
    |> Enum.with_index()
    |> Enum.flat_map(fn {group, position} ->
      definitions
      |> Enum.filter(fn {_key, definition} -> definition.editable == group end)
      |> Enum.sort_by(fn {key, _definition} -> key end)
      |> Enum.map(fn {key, definition} -> {position, build_field(key, definition, scope)} end)
    end)
    |> Enum.sort_by(fn {position, field} -> {position, field.key} end)
    |> Enum.map(fn {_position, field} -> field end)
  end

  @doc """
  The groups a screen can offer, in registry order.

  Useful for diagnostics and for asserting that a screen's declared groups
  exist — a screen naming a group nothing declares renders blank, and nothing
  else would report it.
  """
  @spec groups() :: [String.t()]
  def groups do
    Settings.definitions()
    |> Enum.map(fn {_key, definition} -> definition.editable end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Applies one submission.

  `params` maps setting keys to submitted values; a key absent from `params` is
  left alone, so a screen may submit a subset. Returns the keys that changed,
  split by what happened, which is what a screen needs to tell the user
  something concrete rather than "saved".

  Blank clears the override (see the moduledoc). An encrypted field still
  holding the mask is skipped as untouched.
  """
  @spec save(map(), [field()], Scope.t() | nil) ::
          {:ok, %{written: [String.t()], cleared: [String.t()], unchanged: [String.t()]}}
          | {:error, String.t(), String.t()}
  def save(params, fields, scope) when is_map(params) and is_list(fields) do
    fields
    |> Enum.filter(&Map.has_key?(params, &1.key))
    |> Enum.reduce_while({[], [], []}, fn field, {written, cleared, unchanged} ->
      case apply_field(field, Map.fetch!(params, field.key), scope) do
        :unchanged -> {:cont, {written, cleared, [field.key | unchanged]}}
        :cleared -> {:cont, {written, [field.key | cleared], unchanged}}
        {:ok, _value} -> {:cont, {[field.key | written], cleared, unchanged}}
        {:error, message} -> {:halt, {:error, field.key, message}}
      end
    end)
    |> case do
      {:error, key, message} ->
        {:error, key, message}

      {written, cleared, unchanged} ->
        {:ok,
         %{
           written: Enum.reverse(written),
           cleared: Enum.reverse(cleared),
           unchanged: Enum.reverse(unchanged)
         }}
    end
  end

  @doc """
  Drops every override these fields hold at `scope`.

  Belimbing's `restoreDefaults`: each value then resolves from the next scope
  out, or from the definition's own default. It does not write the defaults —
  writing them would create overrides that merely happen to equal the default
  today and would stop tracking it if it ever changed.
  """
  @spec restore_defaults([field()], Scope.t() | nil) :: {:ok, [String.t()]}
  def restore_defaults(fields, scope) when is_list(fields) do
    cleared =
      fields
      |> Enum.filter(& &1.overridden?)
      |> Enum.map(fn field ->
        :ok = Settings.delete(field.key, scope)
        field.key
      end)

    {:ok, cleared}
  end

  defp build_field(key, definition, scope) do
    scope = narrow_to_allowed(scope, definition)
    stored = Settings.get(key, scope)

    %{
      key: key,
      definition: definition,
      value: display_value(stored, definition, key, scope),
      overridden?: Settings.overridden?(key, scope),
      source_scope: source_scope(key, scope, definition),
      encrypted?: definition.encrypted
    }
  end

  # A screen may be scoped to a user while a definition is only allowed at
  # tenant or global. Reading at a scope the definition does not permit would
  # ask a question the registry has no answer for, so the field resolves at the
  # nearest scope out that the definition does allow.
  defp narrow_to_allowed(scope, definition) do
    scope
    |> Scope.chain()
    |> Enum.find(nil, fn candidate -> scope_type(candidate) in definition.scopes end)
  end

  defp scope_type(nil), do: :global
  defp scope_type(%Scope{type: type}), do: type

  # Never hand a stored secret to the caller: a screen that receives it will
  # eventually render it.
  defp display_value(stored, %Definition{encrypted: true}, key, scope) do
    if Settings.overridden?(key, scope) or present?(stored), do: secret_mask(), else: ""
  end

  defp display_value(stored, _definition, _key, _scope), do: stored

  # Which scope the visible value actually came from -- the first in the
  # cascade that holds an override, or the definition's default at the end.
  defp source_scope(key, scope, definition) do
    scope
    |> Scope.chain()
    |> Enum.filter(&(scope_type(&1) in definition.scopes))
    |> Enum.find(fn candidate -> Settings.overridden?(key, candidate) end)
    |> scope_type()
  end

  defp apply_field(%{definition: definition} = field, submitted, scope) do
    scope = narrow_to_allowed(scope, definition)

    cond do
      field.encrypted? and to_string(submitted) == secret_mask() ->
        :unchanged

      blank?(submitted) and definition.type != :boolean ->
        clear(field, scope)

      true ->
        write(field, submitted, scope)
    end
  end

  defp write(field, submitted, scope) do
    with {:ok, value} <- cast(submitted, field.definition) do
      case Settings.put(field.key, value, scope) do
        {:ok, value} -> {:ok, value}
        {:error, changeset} -> {:error, changeset_message(changeset)}
      end
    end
  end

  @doc """
  Casts one submitted value to the type its definition declares.

  A browser submits strings; `Settings.put/3` raises on a type it did not
  expect, and rightly so — passing an integer setting a string is a caller
  bug. The form is the caller, so the form converts, and a value that cannot
  convert comes back as a message to show rather than an exception.

  Belimbing casts the same way in `normalizeValue`, but reaches it only after
  Laravel validation has already rejected bad input. Nothing plays that role
  here, so this refuses instead of coercing: PHP turns `(int) "abc"` into `0`
  and would save a number the user never typed.
  """
  @spec cast(term(), Definition.t()) :: {:ok, term()} | {:error, String.t()}
  def cast(value, %Definition{} = definition) do
    convert(trim(value), definition)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp convert(value, %Definition{type: :integer}) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, "must be a whole number"}
    end
  end

  defp convert(value, %Definition{type: :float}) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "must be a number"}
    end
  end

  defp convert(value, %Definition{type: :boolean}) when is_binary(value) do
    case String.downcase(value) do
      truthy when truthy in ~w[true 1 on yes] -> {:ok, true}
      falsy when falsy in ~w[false 0 off no] -> {:ok, false}
      _ -> {:error, "must be true or false"}
    end
  end

  # Anything else is already the declared type or is not going to become it:
  # `Definition.accepts?/2` is the same check `Settings.put/3` would raise on,
  # asked where a message can still be shown.
  defp convert(value, %Definition{} = definition) do
    if Definition.accepts?(definition, value) do
      {:ok, value}
    else
      {:error, "must be #{definition.type}"}
    end
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  # Clearing an override that is not there is not an error, but it is also not
  # a change worth reporting -- saying "cleared" about a field that was already
  # inherited would be a lie the user can see through.
  defp clear(field, scope) do
    if Settings.overridden?(field.key, scope) do
      :ok = Settings.delete(field.key, scope)
      :cleared
    else
      :unchanged
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?([]), do: true
  defp blank?(_value), do: false

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true
end
