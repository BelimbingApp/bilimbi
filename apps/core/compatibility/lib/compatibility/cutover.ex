defmodule Bilimbi.Core.Compatibility.Cutover do
  @moduledoc """
  One-shot Belimbing → Bilimbi stored-value remediation, run once at cutover
  after `mix bilimbi.schema.adopt` and before opening traffic.

  Shape already matches by construction (compatible baselines verified by
  `SchemaVerifier`); this step fixes stored VALUES Bilimbi interprets
  differently. Four cases, in the order they matter:

  1. Authz grants naming capabilities Bilimbi does not declare — REPORT ONLY,
     never mutated. Evaluation fails closed (`:denied_unknown_capability`),
     so each such grant is a permanent silent denial for non-`grant_all`
     roles. The capabilities genuinely do not exist, so there is nothing to
     fix: every affected grant is listed for a deliberate operator decision.
     The scan is `Bilimbi.Base.Authz.unknown_persisted_capabilities/1`, the
     owner's own API, so it compares keys exactly the way evaluation does.
  2. `user_pins.url` + `url_hash` — the URL is remapped through the path
     table below; the hash is ALWAYS recomputed with `Pin.hash_url/1` and
     never copied across. The pair is written together.
  3. `notifications.data.url` — `/admin/...` URLs are remapped with the same
     table as pins. Anything else is left alone; `Notification.url/1`
     already returns nil safely for non-relative URLs.
  4. `user_pins.icon` and `user_database_queries.icon` — `heroicon-o-<n>`
     becomes `hero-<n>`, `heroicon-s-<n>` becomes `hero-<n>-solid`, and
     `heroicon-m-<n>` becomes `hero-<n>-mini`. Anything else, including
     NULL, is left untouched and counted as a known remainder. The sampled
     corpus is small by construction, so the remainder is reported rather
     than guessed. An icon is remediated independently of its pin's URL: a
     pin nobody can follow still renders its icon in the sidebar.

  Nothing is deleted. A pin whose URL has no Bilimbi equivalent keeps that
  URL and its stored hash; with nothing removed, the report is the entire
  remedy, so every affected pin is named with its user, label, and dead URL.
  Dedup collisions on `(user_id, url_hash)` resolve non-destructively: the
  pin with the lowest `sort_order` (then lowest id) wins the mapped URL and
  the loser keeps its ORIGINAL Belimbing URL and hash, reported as collision
  residue for the operator to re-pin by hand.

  Counting follows that split. For pins, `changed`, `unchanged`, and
  `unmapped` classify the URL outcome alone and always sum to `examined`;
  `icons_changed` and `remainder` describe icons separately, because a pin
  counted `unchanged` or `unmapped` can still have had its icon repaired.
  For query icons there is no URL, so a row is either `changed` or part of
  the `unmapped` remainder.

  Execution contract: idempotent (every mapping is a fixed point, so a rerun
  reports `changed: 0`), per-table counts, loud failure when a required table
  is absent, a bounded read of the one table that grows without bound
  (`notifications`, paged by `id`), a `--dry-run` read-only mode, and
  `--prefix` to read the same PostgreSQL schema
  `bilimbi.schema.verify` and `bilimbi.schema.adopt` were pointed at. This
  deliberately runs without a tenancy scope: cutover remaps the whole adopted
  database at once, before any tenant traffic exists.
  """

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Repo
  alias Bilimbi.Base.UI.RouteContract
  alias Bilimbi.Core.User.DatabaseQuery
  alias Bilimbi.Core.User.Pin
  alias Ecto.Adapters.SQL

  defmodule Error do
    @moduledoc false
    defexception [:message]
  end

  @type url_kind :: :mapped | :identity | :unmappable

  @type pin_residue :: %{
          required(:pin_id) => pos_integer(),
          required(:user_id) => pos_integer(),
          required(:user_email) => String.t() | nil,
          required(:user_name) => String.t() | nil,
          required(:label) => String.t(),
          required(:url) => String.t() | nil,
          required(:reason) =>
            {:no_bilimbi_route} | {:duplicate_of, pos_integer()} | {:update_failed, String.t()}
        }

  @type report :: %{
          required(:dry_run) => boolean(),
          required(:steps) => %{optional(atom()) => map()}
        }

  # Belimbing path prefix → Bilimbi prefix. The third element renames a
  # trailing `/create` segment to `/new` only for resources whose Bilimbi
  # route actually uses `/new` (users, employees, employee-types); companies
  # and addresses keep `/create`, following the live `web_routes.exs` files
  # rather than the scout report's broader claim.
  @url_prefix_rules [
    {"/admin/companies", "/companies", false},
    {"/admin/employees", "/employees", true},
    {"/admin/employee-types", "/employee-types", true},
    {"/admin/users", "/users", true},
    {"/admin/addresses", "/addresses", false},
    {"/admin/geonames", "/geonames", false},
    {"/admin/roles", "/authz/roles", false},
    {"/admin/audit/actions", "/audit/actions", false},
    {"/admin/audit/mutations", "/audit/mutations", false},
    {"/admin/authz", "/authz", false},
    {"/admin/system/schedule", "/system/schedule", false},
    {"/admin/system/sessions", "/system/sessions", false},
    {"/admin/system/settings", "/system/settings", false},
    {"/admin/system/info", "/system/info", false},
    {"/admin/system/localization", "/system/localization", false},
    {"/admin/system/performance", "/system/performance", false}
  ]

  # Bilimbi route shapes a remapped or already-clean path must match. These
  # are the installed module and host route declarations themselves, read
  # through the manifest Base UI already compiles for `~p` verification, so a
  # renamed or added route cannot leave a stale copy behind here and turn a
  # healthy pin into a reported dead one.
  @known_paths RouteContract.navigable_paths()
               |> Enum.map(fn path ->
                 path
                 |> String.split("/", trim: true)
                 |> Enum.map(fn
                   ":" <> _param -> :param
                   literal -> literal
                 end)
               end)
               |> Enum.uniq()

  if @known_paths == [] do
    raise "no routes are compiled into #{inspect(RouteContract)}; the cutover remap " <>
            "cannot tell a live Bilimbi URL from a dead one without them"
  end

  # Literal segments doubled as route words (new, create, edit, …) can never
  # be a param: `/companies/new` is not a company show page. Without this,
  # the param wildcard would bless reserved words as already-clean paths.
  @literal_segments @known_paths |> List.flatten() |> Enum.filter(&is_binary/1) |> MapSet.new()

  @icon_regex ~r/^heroicon-([osm])-(.+)$/

  @steps [:pins, :query_icons, :notifications, :grants]

  # A prefixed read fails with `undefined_table` when the schema exists and
  # `invalid_schema_name` when it does not; both mean the same thing here.
  @missing_table_codes [:undefined_table, :invalid_schema_name]

  @notification_columns "id::text, type, notifiable_id, data"
  @notification_batch 500

  @doc "The cutover steps, in dependency-safe order."
  @spec steps() :: [atom()]
  def steps, do: @steps

  @doc """
  Classifies a stored URL against the Bilimbing → Bilimbi path table.

  Returns `{:mapped, url}` when a Belimbing-shaped path remaps onto a known
  Bilimbi route, `{:identity, url}` when the path is already a known Bilimbi
  route, and `{:unmappable, url}` otherwise. The returned URL is normalized
  (`Pin.normalize_url/1`); the query string, if any, is carried through.
  """
  @spec classify_url(String.t()) :: {url_kind(), String.t()}
  def classify_url(url) when is_binary(url) do
    normalized = Pin.normalize_url(url)
    {path, query} = split_path_query(normalized)

    cond do
      known_bilimbi_path?(path) ->
        {:identity, normalized}

      true ->
        case remap_path(path) do
          {:ok, mapped_path} when query == "" ->
            if known_bilimbi_path?(mapped_path),
              do: {:mapped, mapped_path},
              else: {:unmappable, normalized}

          {:ok, mapped_path} ->
            candidate = mapped_path <> "?" <> query

            if known_bilimbi_path?(mapped_path),
              do: {:mapped, candidate},
              else: {:unmappable, normalized}

          :error ->
            {:unmappable, normalized}
        end
    end
  end

  @doc """
  Maps a Belimbing icon name onto its Bilimbi `hero-` equivalent.

  Anything outside the `heroicon-o/s/m-` prefixes — including NULL, empty,
  and already-Bilimbi `hero-` names — is `:remainder`: left untouched and
  reported, never guessed.
  """
  @spec map_icon(String.t() | nil) :: {:mapped, String.t()} | :remainder
  def map_icon(nil), do: :remainder
  def map_icon(""), do: :remainder

  def map_icon(icon) when is_binary(icon) do
    case Regex.run(@icon_regex, icon) do
      [_, "o", name] -> {:mapped, "hero-" <> name}
      [_, "s", name] -> {:mapped, "hero-" <> name <> "-solid"}
      [_, "m", name] -> {:mapped, "hero-" <> name <> "-mini"}
      _ -> :remainder
    end
  end

  @doc """
  Runs every cutover step against `repo` (default `Bilimbi.Base.Repo`).

  Options: `:repo`, `:dry_run` (report without writing), `:prefix` (the
  PostgreSQL schema, default `"public"`), and `:declared_capabilities`
  (override for the grants step, defaulting to the live Authz registry).

  Returns `{:ok, report}` with per-table
  examined/changed/unchanged/unmapped counts plus named residue, or
  `{:error, message}` when a required table is absent.
  """
  @spec run(keyword()) :: {:ok, report()} | {:error, String.t()}
  def run(opts \\ []) do
    context = context!(opts)
    steps = Map.new(@steps, fn step -> {step, apply_step(step, context)} end)

    {:ok, %{dry_run: context.dry_run?, steps: steps}}
  rescue
    e in Error -> {:error, e.message}
  end

  defp context!(opts) do
    prefix = Keyword.get(opts, :prefix, "public")

    %{
      repo: Keyword.get(opts, :repo, Repo),
      dry_run?: Keyword.get(opts, :dry_run, false),
      prefix: prefix,
      quoted_prefix: SchemaVerifier.quote_identifier!(prefix),
      declared_capabilities: Keyword.get(opts, :declared_capabilities)
    }
  end

  defp apply_step(:pins, context), do: run_pins(context)
  defp apply_step(:query_icons, context), do: run_query_icons(context)
  defp apply_step(:notifications, context), do: run_notifications(context)
  defp apply_step(:grants, context), do: run_grants(context)

  defp split_path_query(normalized) do
    case String.split(normalized, "?", parts: 2) do
      [path] -> {path, ""}
      [path, query] -> {path, query}
    end
  end

  defp known_bilimbi_path?(path) do
    segments = String.split(path, "/", trim: true)
    Enum.any?(@known_paths, &match_pattern?(&1, segments))
  end

  defp match_pattern?(pattern, segments) when length(pattern) == length(segments) do
    Enum.zip(pattern, segments)
    |> Enum.all?(fn
      {literal, actual} when is_binary(literal) -> literal == actual
      {:param, actual} -> actual not in @literal_segments
    end)
  end

  defp match_pattern?(_pattern, _segments), do: false

  defp remap_path(path) do
    Enum.find_value(@url_prefix_rules, :error, fn {from, to, create_to_new?} ->
      case prefix_rest(path, from) do
        nil ->
          nil

        rest ->
          rest = if create_to_new?, do: rename_create(rest), else: rest
          {:ok, to <> rest}
      end
    end)
  end

  defp prefix_rest(path, prefix) do
    cond do
      path == prefix -> ""
      String.starts_with?(path, prefix <> "/") -> String.slice(path, String.length(prefix)..-1//1)
      true -> nil
    end
  end

  defp rename_create("/create"), do: "/new"
  defp rename_create("/create/" <> rest), do: "/new/" <> rest
  defp rename_create(rest), do: rest

  # Reads pins through raw SQL rather than the Pin schema: the operator
  # report needs the owner's email/name alongside each pin, and Pin carries
  # no users association. Writes still go through `Pin.changeset/2` so URL
  # normalization, hash recomputation, and validation stay canonical.
  defp pins_sql(schema) do
    """
    SELECT p.id, p.user_id, p.label, p.url, p.url_hash, p.icon, p.sort_order, u.email, u.name
    FROM #{schema}.user_pins AS p LEFT JOIN #{schema}.users AS u ON u.id = p.user_id
    ORDER BY p.user_id, p.sort_order, p.id
    """
  end

  defp run_pins(context) do
    rows = query!(context, pins_sql(context.quoted_prefix), [], "user_pins").rows

    state =
      Enum.reduce(rows, empty_pin_state(), fn row, state -> process_pin(row, state, context) end)

    state.counts
    |> Map.put(:residue, Enum.reverse(state.residue))
    |> Map.put(:remainder, remainder_list(state.remainder))
  end

  defp empty_pin_state do
    %{
      counts: %{examined: 0, changed: 0, unchanged: 0, unmapped: 0, icons_changed: 0},
      residue: [],
      remainder: %{},
      taken: %{}
    }
  end

  defp process_pin(
         [id, user_id, label, url, url_hash, icon, _sort, email, name],
         state,
         context
       ) do
    entry = %{
      pin_id: id,
      user_id: user_id,
      user_email: email,
      user_name: name,
      label: label,
      url: url
    }

    pin = %{id: id, user_id: user_id, label: label, url: url, url_hash: url_hash, icon: icon}
    state = bump(state, :examined)

    if is_binary(url) do
      process_pin_row(state, context, entry, pin)
    else
      # The whole row is residue: with no URL there is nothing to normalize
      # and no changeset that would accept a write, icon included.
      state
      |> bump(:unmapped)
      |> add_residue(entry, {:invalid_row, "url is NULL or not a string"})
      |> reserve(pin.user_id, pin.url_hash, pin.id)
    end
  end

  defp process_pin_row(state, context, entry, pin) do
    {state, desired_icon} = classify_icon(state, pin)

    case classify_url(pin.url) do
      {:unmappable, _} ->
        # The dead pin keeps its URL and hash, so it still reserves it.
        state
        |> write_icon(context, pin, desired_icon)
        |> bump(:unmapped)
        |> add_residue(entry, {:no_bilimbi_route})
        |> reserve(pin.user_id, pin.url_hash, pin.id)

      {_kind, effective_url} ->
        remap_pin(state, context, entry, pin, effective_url, desired_icon)
    end
  end

  defp remap_pin(state, context, entry, pin, effective_url, desired_icon) do
    desired_hash = Pin.hash_url(effective_url)

    cond do
      effective_url == pin.url and desired_hash == pin.url_hash ->
        state
        |> write_icon(context, pin, desired_icon)
        |> bump(:unchanged)
        |> reserve(pin.user_id, pin.url_hash, pin.id)

      taken_hash?(state.taken, pin.user_id, desired_hash) ->
        state
        |> write_icon(context, pin, desired_icon)
        |> bump(:unmapped)
        |> add_residue(entry, {:duplicate_of, keeper_id(state.taken, pin.user_id, desired_hash)})
        |> reserve(pin.user_id, pin.url_hash, pin.id)

      true ->
        write_remapped_pin(state, context, entry, pin, effective_url, desired_hash, desired_icon)
    end
  end

  defp write_remapped_pin(state, context, entry, pin, effective_url, desired_hash, desired_icon) do
    case write_pin(context, pin, effective_url, desired_icon) do
      :ok ->
        state
        |> bump(:changed)
        |> count_icon(pin, desired_icon)
        |> reserve(pin.user_id, desired_hash, pin.id)

      {:duplicate} ->
        state
        |> write_icon(context, pin, desired_icon)
        |> bump(:unmapped)
        |> add_residue(entry, {:duplicate_of, occupant_id!(context, pin.user_id, desired_hash)})
        |> reserve(pin.user_id, pin.url_hash, pin.id)

      {:failed, message} ->
        state
        |> write_icon(context, pin, desired_icon)
        |> bump(:unmapped)
        |> add_residue(entry, {:update_failed, message})
        |> reserve(pin.user_id, pin.url_hash, pin.id)
    end
  end

  defp classify_icon(state, pin) do
    case map_icon(pin.icon) do
      {:mapped, mapped} ->
        {state, mapped}

      :remainder ->
        remainder =
          Map.put_new(state.remainder, pin.icon, %{
            icon: pin.icon,
            example_pin_id: pin.id,
            user_id: pin.user_id,
            label: pin.label
          })

        {%{state | remainder: remainder}, pin.icon}
    end
  end

  defp count_icon(state, %{icon: icon}, icon), do: state
  defp count_icon(state, _pin, _desired_icon), do: bump(state, :icons_changed)

  defp bump(state, key), do: %{state | counts: Map.update!(state.counts, key, &(&1 + 1))}

  defp add_residue(state, entry, reason),
    do: %{state | residue: [Map.put(entry, :reason, reason) | state.residue]}

  defp reserve(state, user_id, hash, pin_id) do
    taken =
      Map.update(state.taken, user_id, %{hash => pin_id}, &Map.put_new(&1, hash, pin_id))

    %{state | taken: taken}
  end

  defp taken_hash?(taken, user_id, hash) do
    taken |> Map.get(user_id, %{}) |> Map.has_key?(hash)
  end

  defp keeper_id(taken, user_id, hash) do
    taken |> Map.get(user_id, %{}) |> Map.get(hash)
  end

  # The unique index rejected the write, so the pin holding that hash is one
  # this run has not examined yet and cannot be in `taken`. The index makes
  # the row unique, so the operator gets exactly one pin to re-pin against.
  defp occupant_id!(context, user_id, hash) do
    %{rows: [[id]]} =
      query!(
        context,
        "SELECT id FROM #{context.quoted_prefix}.user_pins WHERE user_id = $1 AND url_hash = $2",
        [user_id, hash],
        "user_pins"
      )

    id
  end

  defp remainder_list(remainder) do
    remainder |> Map.values() |> Enum.sort_by(&inspect(&1.icon))
  end

  # A pin whose URL cannot move still gets its icon repaired: the URL and the
  # hash are deliberately left exactly as Belimbing stored them.
  defp write_icon(state, _context, %{icon: icon}, icon), do: state

  defp write_icon(state, context, pin, desired_icon) do
    unless context.dry_run? do
      changeset =
        context
        |> repo_get!(Pin, pin.id)
        |> Pin.changeset(%{icon: desired_icon})

      update!(context, changeset)
    end

    count_icon(state, pin, desired_icon)
  end

  defp write_pin(%{dry_run?: true}, _pin, _effective_url, _desired_icon), do: :ok

  defp write_pin(context, pin, effective_url, desired_icon) do
    attrs = %{url: effective_url}
    attrs = if desired_icon == pin.icon, do: attrs, else: Map.put(attrs, :icon, desired_icon)

    # `Pin.changeset/2` only recomputes `url_hash` when the URL itself
    # changes, so an already-Bilimbi URL with a stale cross-system hash
    # would round-trip untouched. Force the pair invariant through the same
    # canonical function the changeset uses; never copy a stored hash.
    changeset =
      context
      |> repo_get!(Pin, pin.id)
      |> Pin.changeset(attrs)
      |> Ecto.Changeset.put_change(:url_hash, Pin.hash_url(effective_url))

    case context.repo.update(changeset, prefix: context.prefix) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        if unique_violation?(changeset),
          do: {:duplicate},
          else: {:failed, inspect_errors(changeset)}
    end
  end

  defp repo_get!(context, schema, id), do: context.repo.get!(schema, id, prefix: context.prefix)

  defp update!(context, changeset), do: context.repo.update!(changeset, prefix: context.prefix)

  defp unique_violation?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {message, _}} ->
      message == "has already been taken"
    end)
  end

  defp inspect_errors(changeset) do
    Enum.map_join(changeset.errors, "; ", fn {field, {message, _}} -> "#{field} #{message}" end)
  end

  # Reads query rows through raw SQL; the icon is the only column ever
  # written, through `DatabaseQuery.changeset/2`.
  defp queries_sql(schema) do
    "SELECT id, user_id, name, icon FROM #{schema}.user_database_queries ORDER BY id"
  end

  defp run_query_icons(context) do
    rows =
      query!(context, queries_sql(context.quoted_prefix), [], "user_database_queries").rows

    {counts, remainder} =
      Enum.reduce(rows, {%{examined: 0, changed: 0, unmapped: 0}, %{}}, fn
        [id, user_id, name, icon], {counts, remainder} ->
          counts = Map.update!(counts, :examined, &(&1 + 1))

          case map_icon(icon) do
            {:mapped, mapped} when mapped != icon ->
              write_query_icon(context, id, mapped)
              {Map.update!(counts, :changed, &(&1 + 1)), remainder}

            _ ->
              remainder =
                Map.put_new(remainder, icon, %{
                  icon: icon,
                  example_query_id: id,
                  user_id: user_id,
                  name: name
                })

              {Map.update!(counts, :unmapped, &(&1 + 1)), remainder}
          end
      end)

    Map.put(counts, :remainder, remainder_list(remainder))
  end

  defp write_query_icon(%{dry_run?: true}, _id, _icon), do: :ok

  defp write_query_icon(context, id, icon) do
    changeset =
      context
      |> repo_get!(DatabaseQuery, id)
      |> DatabaseQuery.changeset(%{icon: icon})

    update!(context, changeset)

    :ok
  end

  # Reads notification payloads through raw SQL on purpose: the schema's
  # JSON type masks corrupt payloads as `%{}`, and corrupt rows must be
  # reported loudly, never round-tripped into a write.
  defp notifications_sql(schema, nil) do
    "SELECT #{@notification_columns} FROM #{schema}.notifications " <>
      "ORDER BY id LIMIT #{@notification_batch}"
  end

  defp notifications_sql(schema, _cursor) do
    "SELECT #{@notification_columns} FROM #{schema}.notifications " <>
      "WHERE id > $1::uuid ORDER BY id LIMIT #{@notification_batch}"
  end

  defp run_notifications(context) do
    {counts, residue} =
      reduce_notifications(
        context,
        nil,
        {%{examined: 0, changed: 0, unchanged: 0, unmapped: 0}, []}
      )

    Map.put(counts, :residue, Enum.reverse(residue))
  end

  # `notifications` is the one table here that grows without bound, so it is
  # read one keyset page at a time: a remap rewrites `data` and never `id`,
  # so the cursor stays stable across the writes this step makes.
  defp reduce_notifications(context, cursor, acc) do
    rows = notification_rows(context, cursor)

    acc =
      Enum.reduce(rows, acc, fn row, {counts, residue} ->
        process_notification(context, row, counts, residue)
      end)

    if length(rows) < @notification_batch do
      acc
    else
      reduce_notifications(context, rows |> List.last() |> hd(), acc)
    end
  end

  defp notification_rows(context, nil) do
    query!(context, notifications_sql(context.quoted_prefix, nil), [], "notifications").rows
  end

  defp notification_rows(context, cursor) do
    query!(
      context,
      notifications_sql(context.quoted_prefix, cursor),
      [Ecto.UUID.dump!(cursor)],
      "notifications"
    ).rows
  end

  defp process_notification(context, [id, type, notifiable_id, data], counts, residue) do
    counts = Map.update!(counts, :examined, &(&1 + 1))
    entry = %{notification_id: id, notifiable_id: notifiable_id, type: type}

    case decode_data(data) do
      {:ok, payload} ->
        process_notification_payload(
          context,
          id,
          entry,
          payload,
          payload["url"] || payload[:url],
          counts,
          residue
        )

      {:invalid, _} ->
        entry =
          entry
          |> Map.put(:url, nil)
          |> Map.put(:reason, {:invalid_data, "data is not a JSON object"})

        {Map.update!(counts, :unmapped, &(&1 + 1)), [entry | residue]}
    end
  end

  defp process_notification_payload(_context, _id, _entry, _payload, url, counts, residue)
       when not is_binary(url) or url == "" do
    {Map.update!(counts, :unchanged, &(&1 + 1)), residue}
  end

  defp process_notification_payload(context, id, entry, payload, url, counts, residue) do
    relative? = String.starts_with?(url, "/") and not String.starts_with?(url, "//")

    if relative? do
      case classify_url(url) do
        {:mapped, mapped} ->
          write_notification(context, id, payload, mapped)
          {Map.update!(counts, :changed, &(&1 + 1)), residue}

        {:identity, _} ->
          {Map.update!(counts, :unchanged, &(&1 + 1)), residue}

        {:unmappable, _} ->
          entry = entry |> Map.put(:url, url) |> Map.put(:reason, {:no_bilimbi_route})
          {Map.update!(counts, :unmapped, &(&1 + 1)), [entry | residue]}
      end
    else
      {Map.update!(counts, :unchanged, &(&1 + 1)), residue}
    end
  end

  defp decode_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _ -> {:invalid, data}
    end
  end

  defp decode_data(_), do: {:invalid, nil}

  defp write_notification(%{dry_run?: true}, _id, _payload, _mapped), do: :ok

  defp write_notification(context, id, payload, mapped) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    SQL.query!(
      context.repo,
      "UPDATE #{context.quoted_prefix}.notifications SET data = $1, updated_at = $2 WHERE id = $3::uuid",
      [Jason.encode!(Map.put(payload, "url", mapped)), now, Ecto.UUID.dump!(id)]
    )

    :ok
  end

  # The grants scan belongs to Base Authz: it owns the grant tables, and its
  # diagnostic already compares capability keys exactly the way the evaluator
  # does, so a stored case variant is reported instead of excused. This step
  # only reads; nothing about a grant is ever rewritten.
  defp run_grants(context) do
    opts = [repo: context.repo, prefix: context.prefix]

    opts =
      case context.declared_capabilities do
        nil -> opts
        capabilities -> Keyword.put(opts, :capabilities, capabilities)
      end

    %{role_grants: role_grants, principal_grants: principal_grants} =
      guard_missing_table!("base_authz grant tables", context, fn ->
        Authz.unknown_persisted_capabilities(opts)
      end)

    %{
      undeclared: length(role_grants) + length(principal_grants),
      role_grants: role_grants,
      principal_grants: principal_grants
    }
  end

  defp query!(context, sql, params, table) do
    guard_missing_table!(table, context, fn -> SQL.query!(context.repo, sql, params) end)
  end

  defp guard_missing_table!(table, context, operation) do
    operation.()
  rescue
    e in Postgrex.Error ->
      if e.postgres && e.postgres.code in @missing_table_codes do
        raise Error,
              "cutover remap needs #{table} in schema #{context.prefix}, which is absent. " <>
                "Run after mix bilimbi.schema.adopt on a verified database; never remap values on an unverified schema."
      else
        reraise e, __STACKTRACE__
      end
  end
end
