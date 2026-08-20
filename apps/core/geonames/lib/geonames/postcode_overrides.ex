defmodule Bilimbi.Core.Geonames.PostcodeOverrides do
  @moduledoc false

  import Ecto.Changeset
  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Geonames.Admin1
  alias Bilimbi.Core.Geonames.Country
  alias Bilimbi.Core.Geonames.Postcode
  alias Bilimbi.Core.Geonames.PostcodeOverride

  @type write_error :: :not_found | :stale | Ecto.Changeset.t()

  @doc false
  def changeset(attrs \\ %{}) do
    PostcodeOverride.operator_changeset(%PostcodeOverride{}, attrs)
  end

  @doc false
  def create(attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, override} <- validated_override(%PostcodeOverride{}, attrs),
           {:ok, postcode} <- insert_materialized(override, Repo),
           {:ok, override} <-
             override
             |> change(applied_postcode_id: postcode.id)
             |> Repo.insert() do
        {postcode, override}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> unwrap_transaction()
  end

  def create(_attrs), do: {:error, changeset() |> add_error(:postcode, "is invalid")}

  @doc false
  def update(id, expected_revision, attrs) when is_map(attrs) do
    with {:ok, id} <- positive_id(id) do
      Repo.transaction(fn -> update_locked(id, expected_revision, attrs) end)
      |> unwrap_transaction()
    end
  end

  def update(_id, _expected_revision, _attrs), do: {:error, :not_found}

  @doc false
  def provenance_for(postcodes) when is_list(postcodes) do
    ids = Enum.map(postcodes, & &1.id)

    from(override in PostcodeOverride,
      where: override.applied_postcode_id in ^ids,
      select: {override.applied_postcode_id, override}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc false
  def source_revision(%Postcode{id: id, updated_at: updated_at}) do
    timestamp = if updated_at, do: NaiveDateTime.to_iso8601(updated_at), else: "none"
    "source:#{id}:#{timestamp}"
  end

  @doc false
  def override_revision(%PostcodeOverride{id: id, lock_version: lock_version}) do
    "override:#{id}:#{lock_version}"
  end

  @doc false
  def lock_country(country_iso, repo \\ Repo) do
    country_overrides_query(country_iso)
    |> repo.all()

    :ok
  end

  @doc false
  def reapply_country(country_iso, repo \\ Repo) do
    overrides = repo.all(country_overrides_query(country_iso))

    Enum.each(overrides, &reapply(&1, repo))
    :ok
  end

  defp update_locked(id, expected_revision, attrs) do
    override =
      Repo.one(
        from(override in PostcodeOverride,
          where: override.applied_postcode_id == ^id,
          lock: "FOR UPDATE"
        )
      )

    postcode =
      Repo.one(from(postcode in Postcode, where: postcode.id == ^id, lock: "FOR UPDATE"))

    if postcode do
      if revision_matches?(postcode, override, expected_revision) do
        persist_update(postcode, override, attrs)
      else
        Repo.rollback(:stale)
      end
    else
      Repo.rollback(:not_found)
    end
  end

  defp persist_update(postcode, nil, attrs) do
    override =
      %PostcodeOverride{}
      |> change(
        Map.merge(
          PostcodeOverride.source_attributes(postcode),
          Map.take(Map.from_struct(postcode), PostcodeOverride.materialized_fields())
        )
      )

    with {:ok, override} <- validated_override(override, attrs),
         {:ok, postcode} <- update_materialized(postcode, override, Repo),
         {:ok, override} <-
           override
           |> change(applied_postcode_id: postcode.id)
           |> Repo.insert() do
      {postcode, override}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_update(postcode, override, attrs) do
    with {:ok, changed_override} <- validated_override(override, attrs),
         {:ok, postcode} <- update_materialized(postcode, changed_override, Repo),
         {:ok, changed_override} <-
           changed_override
           |> change()
           |> optimistic_lock(:lock_version)
           |> Repo.update() do
      {postcode, changed_override}
    else
      {:error, %Ecto.StaleEntryError{}} -> Repo.rollback(:stale)
      {:error, reason} -> Repo.rollback(reason)
    end
  rescue
    Ecto.StaleEntryError -> Repo.rollback(:stale)
  end

  defp validated_override(override, attrs) do
    override
    |> PostcodeOverride.operator_changeset(attrs)
    |> validate_country()
    |> validate_admin1()
    |> apply_admin1()
    |> apply_action(:update)
  end

  defp validate_country(changeset) do
    iso = get_field(changeset, :country_iso)

    if is_binary(iso) and Repo.exists?(from(country in Country, where: country.iso == ^iso)) do
      changeset
    else
      add_error(changeset, :country_iso, "is not available")
    end
  end

  defp validate_admin1(changeset) do
    iso = get_field(changeset, :country_iso)
    raw_code = raw_admin1_code(get_field(changeset, :admin1_code), iso)

    cond do
      is_nil(raw_code) ->
        changeset

      raw_code == :invalid ->
        add_error(changeset, :admin1_code, "is not available for the selected country")

      Repo.exists?(from(admin1 in Admin1, where: admin1.code == ^"#{iso}.#{raw_code}")) ->
        put_change(changeset, :admin1_code, raw_code)

      true ->
        add_error(changeset, :admin1_code, "is not available for the selected country")
    end
  end

  defp apply_admin1(changeset) do
    if changeset.valid? do
      iso = get_field(changeset, :country_iso)
      raw_code = get_field(changeset, :admin1_code)

      case raw_code && Repo.get_by(Admin1, code: "#{iso}.#{raw_code}") do
        nil ->
          change(changeset,
            admin1_code: nil,
            admin_name1: nil,
            admin_code1: nil,
            admin_name2: nil,
            admin_code2: nil,
            admin_name3: nil,
            admin_code3: nil
          )

        admin1 ->
          change(changeset,
            admin1_code: raw_code,
            admin_name1: admin1.name,
            admin_code1: raw_code,
            admin_name2: nil,
            admin_code2: nil,
            admin_name3: nil,
            admin_code3: nil
          )
      end
    else
      changeset
    end
  end

  defp raw_admin1_code(nil, _iso), do: nil

  defp raw_admin1_code(code, iso) do
    case String.split(code, ".", parts: 2) do
      [raw] ->
        String.upcase(raw)

      [country, raw] when raw != "" ->
        if String.upcase(country) == iso, do: String.upcase(raw), else: :invalid

      _other ->
        :invalid
    end
  end

  defp insert_materialized(override, repo) do
    %Postcode{}
    |> PostcodeOverride.materialize_changeset(override)
    |> repo.insert()
  end

  defp update_materialized(postcode, override, repo) do
    postcode
    |> PostcodeOverride.materialize_changeset(override)
    |> repo.update()
  end

  defp revision_matches?(postcode, nil, revision),
    do: source_revision(postcode) == revision

  defp revision_matches?(_postcode, override, revision),
    do: override_revision(override) == revision

  defp reapply(override, repo) do
    source = find_source(override, repo)
    previous = repo.get(Postcode, override.applied_postcode_id)
    materialized = source || previous || %Postcode{}

    if source && previous && source.id != previous.id do
      repo.delete!(previous)
    end

    case update_or_insert_materialized(materialized, override, repo) do
      {:ok, postcode} ->
        from(stored in PostcodeOverride, where: stored.id == ^override.id)
        |> repo.update_all(set: [applied_postcode_id: postcode.id])

      {:error, changeset} ->
        repo.rollback({:postcode_override, override.id, changeset})
    end
  end

  defp update_or_insert_materialized(%Postcode{id: nil}, override, repo),
    do: insert_materialized(override, repo)

  defp update_or_insert_materialized(postcode, override, repo),
    do: update_materialized(postcode, override, repo)

  defp find_source(%PostcodeOverride{source_postcode: nil}, _repo), do: nil

  defp find_source(override, repo) do
    fields = PostcodeOverride.materialized_fields()
    source_fields = PostcodeOverride.source_fields()

    predicate =
      Enum.zip(fields, source_fields)
      |> Enum.reduce(dynamic([postcode], true), fn {field_name, source_field}, expression ->
        case Map.fetch!(override, source_field) do
          nil -> dynamic([postcode], ^expression and is_nil(field(postcode, ^field_name)))
          value -> dynamic([postcode], ^expression and field(postcode, ^field_name) == ^value)
        end
      end)

    repo.one(
      from(postcode in Postcode, where: ^predicate, order_by: [asc: postcode.id], limit: 1)
    )
  end

  defp country_overrides_query(country_iso) do
    from(override in PostcodeOverride,
      where:
        override.country_iso == ^country_iso or
          override.source_country_iso == ^country_iso,
      order_by: [asc: override.id],
      lock: "FOR UPDATE"
    )
  end

  defp positive_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp positive_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> {:error, :not_found}
    end
  end

  defp positive_id(_id), do: {:error, :not_found}

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
