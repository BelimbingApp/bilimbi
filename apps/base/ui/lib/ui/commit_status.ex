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
     name the hook pushes to the schema field. Handle `"save_field"` with
     `save_field/4`, which re-asks the capability, resolves the pushed params
     through `inline_field/2` (a name outside the map is ignored and user
     input never becomes an atom) and hands the page its own write.
  3. Perform that write and pass its result to `commit/4`, which records the
     outcome with `put/3`: `:saved` after the page's `:on_ok`, a refusal
     worded by `refusal_message/4` for a changeset, and the page's own noun
     from `:failures` for any other reason, falling through to
     `failure_message/0` for the generic sentence.
  4. Refuse a write from an actor without the capability through
     `write_forbidden/2` with the page's own flash wording.
  5. Read `@field_status[name]` in the template as the `status` of
     `<.inline_edit>` or `<.commit_status>`.

  `Bilimbi.Core.Address.Web.ShowLive`, `Bilimbi.Core.User.Web.ShowLive`,
  `Bilimbi.Core.Employee.Web.ShowLive`, `Bilimbi.Core.Company.Web.ShowLive`
  and `Bilimbi.Core.Employee.Web.TypeShowLive` are the five adopters.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Bilimbi.Base.UI.Components.Forms
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
  Handles the `"save_field"` event of an `<.inline_edit>` text fact.

  Re-asks the capability first: `:can?` is the page's live Authz answer, and
  when it is `false` the write is refused through `write_forbidden/2` with the
  page's `:forbidden` flash, whatever the params say. Otherwise the pushed
  `params` are resolved against `fields` (see `inline_field/2`) and `:write`
  is called with `(socket, name, field, value)`; it performs the page's own
  write, usually through `commit/4`, and returns the socket. Params that name
  no declared fact leave the socket as it is.

  Returns the socket, so a handler is `{:noreply, CommitStatus.save_field(...)}`.
  """
  @spec save_field(Socket.t(), term(), %{name() => atom()},
          can?: boolean(),
          forbidden: String.t(),
          write: (Socket.t(), name(), atom(), String.t() -> Socket.t())
        ) :: Socket.t()
  def save_field(%Socket{} = socket, params, fields, opts) do
    if Keyword.fetch!(opts, :can?) do
      case inline_field(params, fields) do
        {:ok, name, field, value} -> Keyword.fetch!(opts, :write).(socket, name, field, value)
        :error -> socket
      end
    else
      write_forbidden(socket, Keyword.fetch!(opts, :forbidden))
    end
  end

  @doc """
  Records the outcome of the page's own write on the fact `name`.

  `result` is what the write returned. `{:ok, record}` runs `:on_ok` with
  `(socket, record)` so the page can refresh what it shows from the server's
  row, then records `:saved`. `{:error, %Ecto.Changeset{}}` records
  `refusal_message/4` for the schema `:field` the fact writes, named by its
  `:label` and the `:submitted` value. Any other `{:error, reason}` records the
  page's own sentence for that reason from `:failures`, or `failure_message/0`
  when the page has none. Every outcome goes through `put/3`, so "Saved"
  still belongs to the most recent commit only.

  `:failures` is a map from reason to sentence, or a function from reason to
  a sentence or `nil` for a page whose sentence depends on its own state.
  """
  @spec commit(Socket.t(), name(), {:ok, term()} | {:error, term()},
          submitted: term(),
          label: String.t(),
          field: atom(),
          on_ok: (Socket.t(), term() -> Socket.t()),
          failures: %{optional(term()) => String.t()} | (term() -> String.t() | nil)
        ) :: Socket.t()
  def commit(%Socket{} = socket, name, result, opts) do
    case result do
      {:ok, record} ->
        put(Keyword.fetch!(opts, :on_ok).(socket, record), name, :saved)

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          refusal_message(
            Keyword.fetch!(opts, :label),
            Keyword.fetch!(opts, :field),
            Keyword.fetch!(opts, :submitted),
            changeset.errors
          )

        put(socket, name, {:error, message})

      {:error, reason} ->
        put(socket, name, {:error, failure_message(Keyword.get(opts, :failures, %{}), reason)})
    end
  end

  @doc """
  The sentence for a write refused for `reason`, looked up in the page's
  `:failures` (see `commit/4`) and falling through to `failure_message/0`.

  For an outcome a page records itself rather than through `commit/4`.
  """
  @spec failure_message(%{optional(term()) => String.t()} | (term() -> String.t() | nil), term()) ::
          String.t()
  def failure_message(failures, reason) when is_function(failures, 1),
    do: failures.(reason) || failure_message()

  def failure_message(failures, reason) when is_map(failures),
    do: Map.get(failures, reason, failure_message())

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
      case Forms.translate_errors(errors, field) do
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
