defmodule Bilimbi.Base.Grid.ContributionValidator do
  @moduledoc """
  Validates every installed module's `:grid` contribution into one catalog of
  tables, fields and links.

  A contribution is `%{tables: [table_map]}`. Table ids are unique across
  modules; a link's two ends must both be declared tables; a link joins on
  declared fields, and a `:one` link joins on the target's key so a walk can
  never multiply rows. A source or edge module must belong to the module
  that declared it, so no module can put another module's table in the
  catalog under its own capability. Any defect fails the snapshot build, so
  a broken catalog never reaches a page.
  """

  @behaviour Bilimbi.Base.ModuleRegistry.ContributionConsumer

  alias Bilimbi.Base.Grid.Link
  alias Bilimbi.Base.Grid.Source
  alias Bilimbi.Base.Grid.Table

  @type catalog :: %{tables: %{String.t() => Table.t()}}

  @impl true
  @spec validate_contributions!([%{descriptor: map(), payload: term()}]) :: catalog()
  def validate_contributions!(entries) when is_list(entries) do
    {tables, links} =
      Enum.reduce(entries, {[], []}, fn entry, {tables, links} ->
        {entry_tables, entry_links} = entry_tables!(entry)
        {tables ++ entry_tables, links ++ entry_links}
      end)

    table_map = reject_duplicate_ids!(tables)

    table_map =
      Enum.reduce(links, table_map, fn {%Link{} = link, owner}, acc ->
        validate_link!(link, owner, acc)
        Map.update!(acc, link.from, &Table.put_link(&1, link))
      end)

    %{tables: table_map}
  end

  defp entry_tables!(%{descriptor: descriptor, payload: payload}) do
    unless is_map(payload) and Map.keys(payload) == [:tables] and is_list(payload.tables) do
      raise ArgumentError,
            "grid contribution from #{descriptor.id} must be %{tables: [table maps]}"
    end

    Enum.reduce(payload.tables, {[], []}, fn attrs, {tables, links} ->
      unless is_map(attrs) do
        raise ArgumentError, "grid contribution from #{descriptor.id} must contain table maps"
      end

      {table, table_links} = Table.new!(attrs, descriptor.id)
      validate_source!(table, descriptor)
      Enum.each(table_links, &validate_edge!(&1, descriptor))

      {tables ++ [table], links ++ Enum.map(table_links, &{&1, descriptor.id})}
    end)
  end

  defp validate_source!(%Table{source: source} = table, descriptor) do
    unless Code.ensure_loaded?(source) do
      invalid!(
        descriptor.id,
        "source #{inspect(source)} of table #{table.id} could not be loaded"
      )
    end

    unless Source in behaviours(source) do
      invalid!(
        descriptor.id,
        "source #{inspect(source)} of table #{table.id} does not implement #{inspect(Source)}"
      )
    end

    unless owned?(source, descriptor) do
      invalid!(
        descriptor.id,
        "source #{inspect(source)} of table #{table.id} does not belong to #{inspect(descriptor.otp_app)}"
      )
    end
  end

  defp validate_edge!(%Link{via: nil}, _descriptor), do: :ok

  defp validate_edge!(%Link{via: {module, function}} = link, descriptor) do
    unless Code.ensure_loaded?(module) and function_exported?(module, function, 1) do
      invalid!(
        descriptor.id,
        "edge #{inspect(module)}.#{function}/1 of link #{link.id} could not be loaded"
      )
    end

    unless owned?(module, descriptor) do
      invalid!(
        descriptor.id,
        "edge #{inspect(module)} of link #{link.id} does not belong to #{inspect(descriptor.otp_app)}"
      )
    end
  end

  defp owned?(module, descriptor) do
    module in (Application.spec(descriptor.otp_app, :modules) || [])
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp reject_duplicate_ids!(tables) do
    duplicates =
      tables
      |> Enum.group_by(& &1.id)
      |> Enum.filter(fn {_id, group} -> length(group) > 1 end)

    if duplicates != [] do
      detail =
        Enum.map_join(duplicates, "; ", fn {id, group} ->
          "#{id} declared by #{Enum.map_join(group, ", ", & &1.owner)}"
        end)

      raise ArgumentError, "duplicate grid table ids: #{detail}"
    end

    Map.new(tables, &{&1.id, &1})
  end

  defp validate_link!(%Link{} = link, owner, tables) do
    from = fetch_table!(tables, link.from, link, owner)
    to = fetch_table!(tables, link.to, link, owner)

    if Map.has_key?(from.links, link.id) do
      invalid!(owner, "link #{link.id} is declared twice on table #{from.id}")
    end

    if Map.has_key?(from.fields, link.id) do
      invalid!(owner, "link #{link.id} on table #{from.id} has the same id as a field")
    end

    case link.on do
      {from_field, to_field} ->
        unless Map.has_key?(from.fields, from_field) do
          invalid!(
            owner,
            "link #{link.id} joins on #{from.id}.#{from_field}, which is not declared"
          )
        end

        unless Map.has_key?(to.fields, to_field) do
          invalid!(owner, "link #{link.id} joins on #{to.id}.#{to_field}, which is not declared")
        end

        if link.kind == :one and to_field != to.key do
          invalid!(
            owner,
            "link #{link.id} is :one but joins on #{to.id}.#{to_field} rather than its key #{to.key}"
          )
        end

      nil ->
        :ok
    end
  end

  defp fetch_table!(tables, id, link, owner) do
    case Map.fetch(tables, id) do
      {:ok, table} ->
        table

      :error ->
        invalid!(owner, "link #{link.id} names table #{inspect(id)}, which no module declares")
    end
  end

  defp invalid!(owner, message) do
    raise ArgumentError, "invalid grid contribution from #{owner}: #{message}"
  end
end
