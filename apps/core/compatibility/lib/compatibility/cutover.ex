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
     fix: every affected grant is listed with role code, principal, and
     capability for a deliberate operator decision.
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
     than guessed.

  Nothing is deleted. A pin whose URL has no Bilimbi equivalent stays
  byte-identical in place; with nothing removed, the report is the entire
  remedy, so every affected pin is named with its user, label, and dead URL.
  Dedup collisions on `(user_id, url_hash)` resolve non-destructively: the
  pin with the lowest `sort_order` (then lowest id) wins the mapped URL and
  the loser keeps its ORIGINAL Belimbing URL and hash, reported as collision
  residue for the operator to re-pin by hand.

  Execution contract: idempotent (every mapping is a fixed point, so a rerun
  reports `changed: 0`), per-table examined/changed/unchanged/unmapped
  counts, loud failure when a required table is absent, a `--dry-run`
  read-only mode, and `--strict` to turn residue into failure for rehearsals.
  This deliberately runs without a tenancy scope: cutover remaps the whole
  adopted database at once, before any tenant traffic exists.
  """

  alias Bilimbi.Base.Authz
  alias Bilimbi.Base.Repo
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

  # Bilimbi route shapes a remapped or already-clean path must match.
  # `:id`/`:slug` match any single segment; literals must match exactly, so
  # `/companies/create` wins over `/companies/:id` while `/companies/new`
  # (no such page) stays unmappable. Mirrors `apps/*/priv/web_routes.exs`.
  @known_paths [
    ["companies"],
    ["companies", "create"],
    ["companies", :id],
    ["companies", :id, "departments"],
    ["companies", :id, "relationships"],
    ["companies", "legal-entity-types"],
    ["companies", "department-types"],
    ["employees"],
    ["employees", "new"],
    ["employees", :id],
    ["employees", :id, "edit"],
    ["employee-types"],
    ["employee-types", "new"],
    ["employee-types", :id, "edit"],
    ["users"],
    ["users", "new"],
    ["users", :id],
    ["users", :id, "edit"],
    ["addresses"],
    ["addresses", "create"],
    ["addresses", :id],
    ["geonames", "countries"],
    ["geonames", "admin1"],
    ["geonames", "postcodes"],
    ["authz", "roles"],
    ["authz", "roles", "create"],
    ["authz", "roles", :id],
    ["authz", "capabilities"],
    ["authz", "principal-roles"],
    ["authz", "principal-capabilities"],
    ["authz", "decision-logs"],
    ["audit", "actions"],
    ["audit", "mutations"],
    ["system", "schedule"],
    ["system", "sessions"],
    ["system", "settings"],
    ["system", "info"],
    ["system", "localization"],
    ["system", "performance"],
    ["admin", "system", "database-queries"],
    ["admin", "system", "database-queries", :slug],
    ["settings", "profile"],
    ["settings", "password"],
    ["settings", "appearance"],
    ["notifications"],
    ["dashboard"]
  ]

  @icon_regex ~r/^heroicon-([osm])-(.+)$/

  @steps [:pins, :query_icons, :notifications, :grants]

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
  Runs the requested cutover steps against `repo` (default `Bilimbi.Base.Repo`).

  Options: `:repo`, `:dry_run` (report without writing), `:only` (subset of
  `steps/0`), `:declared_capabilities` (override for the grants step,
  defaulting to the live Authz registry).

  Returns `{:ok, report}` with per-table
  examined/changed/unchanged/unmapped counts plus named residue, or
  `{:error, message}` when a required table is absent.
  """
  @spec run(keyword()) :: {:ok, report()} | {:error, String.t()}
  def run(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    dry_run? = Keyword.get(opts, :dry_run, false)
    only = parse_only!(Keyword.get(opts, :only, @steps))
    step_opts = [repo: repo, dry_run: dry_run?] ++ Keyword.take(opts, [:declared_capabilities])

    steps =
      Enum.reduce(only, %{}, fn step, acc ->
        Map.put(acc, step, apply_step(step, step_opts))
      end)

    {:ok, %{dry_run: dry_run?, steps: steps}}
  rescue
    e in Error -> {:error, e.message}
  end

  @doc """
  True when the report holds residue an operator must disposition: unmapped
  pins, unmapped notification URLs, or grants naming undeclared capabilities.
  Icon remainders are cosmetic and expected, so they never count here.
  """
  @spec strict_residue?(report()) :: boolean()
  def strict_residue?(%{steps: steps}) do
    Enum.any?([:pins, :notifications, :grants], fn step ->
      case Map.get(steps, step) do
        %{unmapped: unmapped} when is_integer(unmapped) -> unmapped > 0
        _ -> false
      end
    end)
  end

  defp parse_only!(nil), do: @steps

  defp parse_only!(only) when is_list(only) do
    Enum.map(only, &normalize_step!/1)
  end

  defp parse_only!(only) when is_atom(only) or is_binary(only), do: [normalize_step!(only)]

  defp normalize_step!(:query_icons), do: :query_icons
  defp normalize_step!(:pins), do: :pins
  defp normalize_step!(:notifications), do: :notifications
  defp normalize_step!(:grants), do: :grants
  defp normalize_step!("pins"), do: :pins
  defp normalize_step!("query_icons"), do: :query_icons
  defp normalize_step!("query-icons"), do: :query_icons
  defp normalize_step!("icons"), do: :query_icons
  defp normalize_step!("notifications"), do: :notifications
  defp normalize_step!("grants"), do: :grants

  defp normalize_step!(other) do
    raise Error,
          "unknown cutover step #{inspect(other)}; expected one of pins, query_icons, notifications, grants"
  end

  defp apply_step(:pins, opts), do: run_pins(opts)
  defp apply_step(:query_icons, opts), do: run_query_icons(opts)
  defp apply_step(:notifications, opts), do: run_notifications(opts)
  defp apply_step(:grants, opts), do: run_grants(opts)

  defp split_path_query(normalized) do
    case String.split(normalized, "?", parts: 2) do
      [path] -> {path, ""}
      [path, query] -> {path, query}
    end
  end

  # Literal segments doubled as route words (new, create, edit, …) can never
  # be an `:id`: `/companies/new` is not a company show page. Without this,
  # the `:id` wildcard would bless reserved words as already-clean paths.
  @literal_segments @known_paths |> List.flatten() |> Enum.filter(&is_binary/1) |> MapSet.new()

  defp known_bilimbi_path?(path) do
    segments = String.split(path, "/", trim: true)
    Enum.any?(@known_paths, &match_pattern?(&1, segments))
  end

  defp match_pattern?(pattern, segments) when length(pattern) == length(segments) do
    Enum.zip(pattern, segments)
    |> Enum.all?(fn
      {literal, actual} when is_binary(literal) -> literal == actual
      {_param, actual} -> actual not in @literal_segments
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
  @pins_sql """
  SELECT p.id, p.user_id, p.label, p.url, p.url_hash, p.icon, p.sort_order, u.email, u.name
  FROM user_pins AS p LEFT JOIN users AS u ON u.id = p.user_id
  ORDER BY p.user_id, p.sort_order, p.id
  """

  defp run_pins(opts) do
    repo = Keyword.fetch!(opts, :repo)
    dry_run? = Keyword.get(opts, :dry_run, false)

    rows = query!(repo, @pins_sql, [], "user_pins").rows

    {counts, residue, _taken} =
      Enum.reduce(rows, {%{examined: 0, changed: 0, unchanged: 0, unmapped: 0}, [], %{}}, fn
        row, {counts, residue, taken} ->
          process_pin(repo, dry_run?, row, counts, residue, taken)
      end)

    Map.put(counts, :residue, Enum.reverse(residue))
  end

  defp process_pin(
         repo,
         dry_run?,
         [id, user_id, label, url, url_hash, icon, _sort, email, name],
         counts,
         residue,
         taken
       ) do
    counts = Map.update!(counts, :examined, &(&1 + 1))

    entry = %{
      pin_id: id,
      user_id: user_id,
      user_email: email,
      user_name: name,
      label: label,
      url: url
    }

    if not is_binary(url) do
      counts = Map.update!(counts, :unmapped, &(&1 + 1))
      residue = [Map.put(entry, :reason, {:invalid_row, "url is NULL or not a string"}) | residue]
      {counts, residue, remember_taken(taken, user_id, url_hash, id)}
    else
      process_pin_url(
        repo,
        dry_run?,
        entry,
        url,
        url_hash,
        icon,
        id,
        user_id,
        counts,
        residue,
        taken
      )
    end
  end

  defp process_pin_url(
         repo,
         dry_run?,
         entry,
         url,
         url_hash,
         icon,
         id,
         user_id,
         counts,
         residue,
         taken
       ) do
    case classify_url(url) do
      {:unmappable, _} ->
        counts = Map.update!(counts, :unmapped, &(&1 + 1))
        residue = [Map.put(entry, :reason, {:no_bilimbi_route}) | residue]
        # The dead pin keeps its hash in the database, so it still reserves it.
        {counts, residue, remember_taken(taken, user_id, url_hash, id)}

      {_, effective_url} ->
        desired_icon =
          case map_icon(icon) do
            {:mapped, mapped} -> mapped
            :remainder -> icon
          end

        desired_hash = Pin.hash_url(effective_url)

        cond do
          effective_url == url and desired_hash == url_hash and desired_icon == icon ->
            counts = Map.update!(counts, :unchanged, &(&1 + 1))
            {counts, residue, remember_taken(taken, user_id, url_hash, id)}

          taken_hash?(taken, user_id, desired_hash) ->
            keeper = keeper_id(taken, user_id, desired_hash)
            counts = Map.update!(counts, :unmapped, &(&1 + 1))
            residue = [Map.put(entry, :reason, {:duplicate_of, keeper}) | residue]
            {counts, residue, remember_taken(taken, user_id, url_hash, id)}

          true ->
            case write_pin(repo, dry_run?, id, effective_url, icon, desired_icon) do
              :ok ->
                counts = Map.update!(counts, :changed, &(&1 + 1))
                {counts, residue, remember_taken(taken, user_id, desired_hash, id)}

              {:duplicate} ->
                counts = Map.update!(counts, :unmapped, &(&1 + 1))
                keeper = keeper_id(taken, user_id, desired_hash)
                residue = [Map.put(entry, :reason, {:duplicate_of, keeper}) | residue]
                {counts, residue, remember_taken(taken, user_id, url_hash, id)}

              {:failed, message} ->
                counts = Map.update!(counts, :unmapped, &(&1 + 1))
                residue = [Map.put(entry, :reason, {:update_failed, message}) | residue]
                {counts, residue, remember_taken(taken, user_id, url_hash, id)}
            end
        end
    end
  end

  defp remember_taken(taken, user_id, hash, pin_id) do
    Map.update(taken, user_id, %{hash => pin_id}, &Map.put_new(&1, hash, pin_id))
  end

  defp taken_hash?(taken, user_id, hash) do
    taken |> Map.get(user_id, %{}) |> Map.has_key?(hash)
  end

  defp keeper_id(taken, user_id, hash) do
    taken |> Map.get(user_id, %{}) |> Map.get(hash)
  end

  defp write_pin(_repo, true = _dry_run?, _id, _url, _icon, _desired_icon), do: :ok

  defp write_pin(repo, false, id, effective_url, icon, desired_icon) do
    attrs = %{url: effective_url}
    attrs = if desired_icon == icon, do: attrs, else: Map.put(attrs, :icon, desired_icon)

    # `Pin.changeset/2` only recomputes `url_hash` when the URL itself
    # changes, so an already-Bilimbi URL with a stale cross-system hash
    # would round-trip untouched. Force the pair invariant through the same
    # canonical function the changeset uses; never copy a stored hash.
    changeset =
      repo.get!(Pin, id)
      |> Pin.changeset(attrs)
      |> Ecto.Changeset.put_change(:url_hash, Pin.hash_url(effective_url))

    case repo.update(changeset) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        if unique_violation?(changeset),
          do: {:duplicate},
          else: {:failed, inspect_errors(changeset)}
    end
  end

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
  @queries_sql "SELECT id, user_id, name, icon FROM user_database_queries ORDER BY id"

  defp run_query_icons(opts) do
    repo = Keyword.fetch!(opts, :repo)
    dry_run? = Keyword.get(opts, :dry_run, false)

    rows = query!(repo, @queries_sql, [], "user_database_queries").rows

    {counts, remainder} =
      Enum.reduce(rows, {%{examined: 0, changed: 0, unchanged: 0, unmapped: 0}, %{}}, fn
        [id, user_id, name, icon], {counts, remainder} ->
          counts = Map.update!(counts, :examined, &(&1 + 1))

          case map_icon(icon) do
            {:mapped, mapped} when mapped != icon ->
              write_query_icon(repo, dry_run?, id, mapped)
              {Map.update!(counts, :changed, &(&1 + 1)), remainder}

            _ ->
              remainder =
                Map.update(
                  remainder,
                  icon,
                  %{icon: icon, example_query_id: id, user_id: user_id, name: name},
                  & &1
                )

              {counts |> Map.update!(:unchanged, &(&1 + 1)) |> Map.update!(:unmapped, &(&1 + 1)),
               remainder}
          end
      end)

    counts
    |> Map.put(:remainder, remainder |> Map.values() |> Enum.sort_by(&inspect(&1.icon)))
  end

  defp write_query_icon(_repo, true = _dry_run?, _id, _icon), do: :ok

  defp write_query_icon(repo, false, id, icon) do
    repo.get!(DatabaseQuery, id)
    |> DatabaseQuery.changeset(%{icon: icon})
    |> repo.update!()

    :ok
  end

  # Reads notification payloads through raw SQL on purpose: the schema's
  # JSON type masks corrupt payloads as `%{}`, and corrupt rows must be
  # reported loudly, never round-tripped into a write.
  @notifications_sql "SELECT id::text, type, notifiable_id, data FROM notifications ORDER BY id"

  defp run_notifications(opts) do
    repo = Keyword.fetch!(opts, :repo)
    dry_run? = Keyword.get(opts, :dry_run, false)

    rows = query!(repo, @notifications_sql, [], "notifications").rows

    {counts, residue} =
      Enum.reduce(rows, {%{examined: 0, changed: 0, unchanged: 0, unmapped: 0}, []}, fn
        row, {counts, residue} ->
          process_notification(repo, dry_run?, row, counts, residue)
      end)

    Map.put(counts, :residue, Enum.reverse(residue))
  end

  defp process_notification(repo, dry_run?, [id, type, notifiable_id, data], counts, residue) do
    counts = Map.update!(counts, :examined, &(&1 + 1))
    entry = %{notification_id: id, notifiable_id: notifiable_id, type: type}

    case decode_data(data) do
      {:ok, payload} ->
        process_notification_payload(
          repo,
          dry_run?,
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

  defp process_notification_payload(_repo, _dry_run?, _id, _entry, _payload, url, counts, residue)
       when not is_binary(url) or url == "" do
    {Map.update!(counts, :unchanged, &(&1 + 1)), residue}
  end

  defp process_notification_payload(repo, dry_run?, id, entry, payload, url, counts, residue) do
    relative? = String.starts_with?(url, "/") and not String.starts_with?(url, "//")

    if relative? do
      case classify_url(url) do
        {:mapped, mapped} ->
          write_notification(repo, dry_run?, id, payload, mapped)
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

  defp write_notification(_repo, true = _dry_run?, _id, _payload, _mapped), do: :ok

  defp write_notification(repo, false, id, payload, mapped) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    SQL.query!(
      repo,
      "UPDATE notifications SET data = $1, updated_at = $2 WHERE id = $3::uuid",
      [Jason.encode!(Map.put(payload, "url", mapped)), now, Ecto.UUID.dump!(id)]
    )

    :ok
  end

  # Grant rows are read through raw SQL with the owning descriptor's table
  # names: Authz exposes no "rewrite my grants" API (and must not gain one
  # for a one-shot cutover), and this step never writes in any case.
  @role_grants_sql """
  SELECT rc.id, rc.role_id, rc.capability_key, r.code, r.company_id, r.grant_all
  FROM base_authz_role_capabilities AS rc JOIN base_authz_roles AS r ON r.id = rc.role_id
  ORDER BY rc.id
  """

  @principal_grants_sql """
  SELECT id, company_id, principal_type, principal_id, capability_key, is_allowed
  FROM base_authz_principal_capabilities
  ORDER BY id
  """

  defp run_grants(opts) do
    repo = Keyword.fetch!(opts, :repo)
    declared = declared_capabilities(opts)

    role_rows = query!(repo, @role_grants_sql, [], "base_authz_role_capabilities").rows

    principal_rows =
      query!(repo, @principal_grants_sql, [], "base_authz_principal_capabilities").rows

    {role_affected, role_clean} =
      Enum.split_with(role_rows, fn [_id, _role_id, capability | _] ->
        unknown?(declared, capability)
      end)

    {principal_affected, principal_clean} =
      Enum.split_with(principal_rows, fn [_id, _company, _type, _pid, capability | _] ->
        unknown?(declared, capability)
      end)

    %{
      examined: length(role_rows) + length(principal_rows),
      changed: 0,
      unchanged: length(role_clean) + length(principal_clean),
      unmapped: length(role_affected) + length(principal_affected),
      role_grants:
        Enum.map(role_affected, fn [id, role_id, capability, code, company_id, grant_all] ->
          %{
            grant_id: id,
            role_id: role_id,
            role_code: code,
            company_id: company_id,
            grant_all: grant_all,
            capability: capability
          }
        end),
      principal_grants:
        Enum.map(principal_affected, fn [
                                          id,
                                          company_id,
                                          principal_type,
                                          principal_id,
                                          capability,
                                          is_allowed
                                        ] ->
          %{
            grant_id: id,
            company_id: company_id,
            principal_type: principal_type,
            principal_id: principal_id,
            capability: capability,
            is_allowed: is_allowed
          }
        end)
    }
  end

  defp declared_capabilities(opts) do
    caps =
      case Keyword.fetch(opts, :declared_capabilities) do
        {:ok, caps} -> caps
        :error -> Authz.capabilities()
      end

    caps |> Enum.map(&String.downcase/1) |> MapSet.new()
  end

  defp unknown?(declared, capability) when is_binary(capability) do
    not MapSet.member?(declared, String.downcase(capability))
  end

  defp unknown?(_declared, _capability), do: true

  defp query!(repo, sql, params, table) do
    SQL.query!(repo, sql, params)
  rescue
    e in Postgrex.Error ->
      if e.postgres && e.postgres.code == :undefined_table do
        raise Error,
              "cutover remap needs table #{table}, which is absent. " <>
                "Run after mix bilimbi.schema.adopt on a verified database; never remap values on an unverified schema."
      else
        reraise e, __STACKTRACE__
      end
  end
end
