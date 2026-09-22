defmodule Bilimbi.Base.UI.CommitStatus do
  # The one statement of how much of a rejected value the alert repeats.
  @rejected_value_limit 60

  @moduledoc """
  Per-fact commit outcome bookkeeping for read-first detail pages.

  `<.inline_edit>` and `<.commit_status>` in `Bilimbi.Base.UI.Components`
  render the outcome of one commit beside the fact that made it. This module
  owns what those components consume: the `:field_status` assign that maps a
  fact name to its outcome, the rules that decide which outcomes stand, and
  the wording of a refusal. A page keeps none of this itself; it keeps only
  what is genuinely its own — the write it performs, the nouns of its failure
  messages and the wording of its forbidden flash.

  ## The vocabulary

  A status is `nil` (nothing to report), `:saved` (the last commit was
  stored) or `{:error, message}` (the last commit was refused and `message`
  says why). `normalize/1` is the one place that shape is checked.

  ## The rules

    * "Saved" belongs to the most recent commit only. Every `put/3` drops
      every standing `:saved` before recording the new outcome, whatever the
      new outcome is, so no stale "Saved" reads as if a later write had landed
      too. A refusal stays on its fact until that fact is committed again, so
      a success elsewhere never clears another fact's refusal.
    * A refused write from an actor who lost the capability is the whole
      outcome: `write_forbidden/2` drops every "Saved" and reports through
      the page's error flash.
    * A refusal names what was typed so it is never anonymous, but a long
      rejected value would push the reason off screen. `rejected_value/1`
      keeps the first #{@rejected_value_limit} characters and marks the cut with an ellipsis.

  ## Adopting it on a page

  1. `alias Bilimbi.Base.UI.CommitStatus` and call `init/1` in `mount/3`.
  2. Declare the facts an inline text edit may write as a map from the form
     name the hook pushes to the schema field, and resolve the pushed params
     through `inline_field/2`; a name outside the map is ignored and user
     input never becomes an atom.
  3. After the page's own write, record the outcome with `put/3`: `:saved`
     on success, `{:error, refusal_message(...)}` on a changeset refusal, and
     `{:error, message}` with the page's own noun for any other reason,
     falling through to `failure_message/0` for the generic sentence.
  4. Refuse a write from an actor without the capability through
     `write_forbidden/2` with the page's own flash wording.
  5. Read `@field_status[name]` in the template as the `status` of
     `<.inline_edit>` or `<.commit_status>`.

  `Bilimbi.Core.Address.Web.ShowLive` and `Bilimbi.Core.User.Web.ShowLive`
  are the two adopters.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Phoenix.LiveView.Socket

  @type name :: String.t()
  @type status :: nil | :saved | {:error, String.t()}

  @assign :field_status

  @doc """
  Assigns the empty `:field_status` map; call it once in `mount/3`.
  """
  @spec init(Socket.t()) :: Socket.t()
  def init(%Socket{} = socket), do: assign(socket, @assign, %{})

  @doc """
  Records the outcome of the most recent commit on the fact `name`.

  Every standing "Saved" is dropped first, whatever the new outcome is; a
  refusal recorded on another fact stays until that fact is committed again.
  Raises `ArgumentError` for a status outside the vocabulary.
  """
  @spec put(Socket.t(), name(), status()) :: Socket.t()
  def put(%Socket{} = socket, name, status) when is_binary(name) do
    statuses =
      socket.assigns
      |> Map.fetch!(@assign)
      |> drop_saved()
      |> Map.put(name, normalize(status))

    assign(socket, @assign, statuses)
  end

  @doc """
  Refuses a write the actor may no longer perform.

  The refusal is the whole outcome: a "Saved" left over from an earlier commit
  would read as if this write had landed too, so every one is dropped and the
  page's `message` is reported through the error flash.
  """
  @spec write_forbidden(Socket.t(), String.t()) :: Socket.t()
  def write_forbidden(%Socket{} = socket, message) when is_binary(message) do
    statuses = socket.assigns |> Map.fetch!(@assign) |> drop_saved()

    socket
    |> assign(@assign, statuses)
    |> put_flash(:error, message)
  end

  @doc """
  Resolves the inline text fact an `InlineEdit` hook committed.

  `fields` maps each form name the hook may push to the schema field it
  writes. Returns `{:ok, name, field, value}` for the first declared name
  present in `params` with a string value, and `:error` for anything else.
  """
  @spec inline_field(term(), %{name() => atom()}) ::
          {:ok, name(), atom(), String.t()} | :error
  def inline_field(params, fields) when is_map(params) and is_map(fields) do
    Enum.find_value(fields, :error, fn {name, field} ->
      case Map.fetch(params, name) do
        {:ok, value} when is_binary(value) -> {:ok, name, field, value}
        _ -> nil
      end
    end)
  end

  def inline_field(_params, fields) when is_map(fields), do: :error

  @doc """
  The alert for a commit the changeset refused.

  Names the rejected value (see `rejected_value/1`), the fact's `label`, and
  every translated error the changeset holds for `field`, or "could not be
  saved" when it holds none. `errors` is the changeset's `errors` list.
  """
  @spec refusal_message(String.t(), atom(), term(), keyword()) :: String.t()
  def refusal_message(label, field, submitted, errors)
      when is_binary(label) and is_atom(field) and is_list(errors) do
    reasons =
      case Bilimbi.Base.UI.Components.translate_errors(errors, field) do
        [] -> ["could not be saved"]
        messages -> messages
      end

    "#{inspect(rejected_value(submitted))} was not saved: #{label} #{Enum.join(reasons, ", ")}."
  end

  @doc """
  The part of a rejected value an alert repeats.

  The first #{@rejected_value_limit} characters of the trimmed value identify
  it; a longer value is cut there and marked with an ellipsis so the reason
  that refused it stays on screen.
  """
  @spec rejected_value(term()) :: String.t()
  def rejected_value(submitted) do
    trimmed = String.trim(to_string(submitted))

    if String.length(trimmed) > @rejected_value_limit do
      String.slice(trimmed, 0, @rejected_value_limit) <> "…"
    else
      trimmed
    end
  end

  @doc """
  The sentence for a write refused for a reason the page has no noun for.
  """
  @spec failure_message() :: String.t()
  def failure_message,
    do: "The change was not saved. Try again, and tell your administrator if it keeps failing."

  @doc """
  Checks a status against the vocabulary and returns it unchanged.

  `<.inline_edit>` and `<.commit_status>` normalize through here too, so a
  status outside the vocabulary fails wherever it first appears.
  """
  @spec normalize(term()) :: status()
  def normalize(nil), do: nil
  def normalize(:saved), do: :saved
  def normalize({:error, message} = status) when is_binary(message), do: status

  def normalize(other) do
    raise ArgumentError,
          "status must be nil, :saved, or {:error, message}, got: #{inspect(other)}"
  end

  defp drop_saved(statuses) when is_map(statuses) do
    statuses
    |> Enum.reject(fn {_name, value} -> value == :saved end)
    |> Map.new()
  end
end
