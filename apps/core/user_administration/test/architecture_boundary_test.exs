defmodule Bilimbi.Core.UserAdministration.ArchitectureBoundaryTest do
  use ExUnit.Case, async: true

  @module_root Path.expand("..", __DIR__)
  @workspace_root Path.expand("../../..", @module_root)
  @query_file Path.join(@module_root, "lib/user_administration/query.ex")
  @physical_relations [
    "users",
    "companies",
    "base_authz_principal_roles",
    "base_authz_roles"
  ]
  @forbidden_owner_schemas [
    [:Bilimbi, :Core, :User, :Schema],
    [:Bilimbi, :Core, :Company, :Schema],
    [:Bilimbi, :Base, :Authz, :PrincipalRole],
    [:Bilimbi, :Base, :Authz, :Role]
  ]

  test "the descriptor has exactly the reviewed graph and no product contribution" do
    {descriptor, _binding} = Code.eval_file(Path.join(@module_root, "bilimbi.module.exs"))

    assert descriptor == [
             id: "core/user_administration",
             kind: :module,
             layer: :core,
             required: true,
             otp_app: :bilimbi_core_user_administration,
             namespace: Bilimbi.Core.UserAdministration,
             dependencies: [
               "base/authz",
               "base/database",
               "base/module_registry",
               "base/tenancy",
               "core/company",
               "core/user"
             ],
             migrations: nil,
             web: nil,
             schema_contract: nil,
             contribution_provider: nil
           ]
  end

  test "the four schema-less physical sources exist once at approved Query source positions" do
    sites =
      @workspace_root
      |> Path.join("apps/*/*/lib/**/*.{ex,exs}")
      |> Path.wildcard()
      |> Enum.flat_map(&physical_source_sites/1)
      |> Enum.sort_by(& &1.relation)

    assert Enum.map(sites, & &1.relation) == Enum.sort(@physical_relations)

    assert Enum.all?(sites, fn site ->
             site.file == @query_file and is_integer(site.line) and site.line > 0 and
               is_integer(site.column) and site.column > 0
           end)
  end

  test "each approved source binding reads exactly its versioned column allowlist" do
    ast = parsed!(@query_file)

    assert fields_in(ast, :tenant_companies, :company) ==
             MapSet.new([:id, :tenant_id, :name, :deleted_at])

    assert fields_in(ast, :filtered_users, :user) ==
             MapSet.new([:id, :company_id, :name, :email, :created_at])

    assert fields_in(ast, :visible_role_assignments, :assignment) ==
             MapSet.new([:company_id, :principal_type, :principal_id, :role_id])

    assert fields_in(ast, :visible_role_assignments, :role) ==
             MapSet.new([:id, :company_id, :name, :code, :is_system])
  end

  test "package code imports no owner schema and has no persistence escape or write" do
    package_files = Path.wildcard(Path.join(@module_root, "lib/**/*.{ex,exs}"))

    aliases = Enum.flat_map(package_files, &aliases_in/1)
    assert Enum.filter(aliases, &(&1 in @forbidden_owner_schemas)) == []

    repo_calls = Enum.flat_map(package_files, &repo_calls_in/1)
    assert repo_calls == [{@query_file, :all}]

    fragments = Enum.flat_map(package_files, &fragment_calls_in/1)
    assert length(fragments) == 4

    assert Enum.all?(fragments, fn %{file: file, sql: sql, line: line} ->
             file == @query_file and is_binary(sql) and is_integer(line) and line > 0 and
               not String.contains?(sql, [<<35, 123>>, ";", "--"])
           end)

    assert dynamic_sources_in(@query_file) == []
  end

  defp physical_source_sites(file) do
    file
    |> parsed!()
    |> Macro.prewalk([], fn
      {:in, meta, [_binding, relation]} = node, sites when relation in @physical_relations ->
        {node, [site(file, relation, meta) | sites]}

      {:from, meta, [relation | _arguments]} = node, sites when relation in @physical_relations ->
        {node, [site(file, relation, meta) | sites]}

      {{:., _dot_meta, [_receiver, :scope_query]}, meta, [relation | _args]} = node, sites
      when relation in @physical_relations ->
        {node, [site(file, relation, meta) | sites]}

      node, sites ->
        {node, sites}
    end)
    |> elem(1)
  end

  defp site(file, relation, meta) do
    %{file: file, relation: relation, line: meta[:line], column: meta[:column]}
  end

  defp fields_in(ast, function_name, binding_name) do
    body = function_body!(ast, function_name)

    body
    |> Macro.prewalk(MapSet.new(), fn
      {{:., _dot_meta, [{^binding_name, _binding_meta, _context}, field]}, _call_meta, []} = node,
      fields
      when is_atom(field) ->
        {node, MapSet.put(fields, field)}

      node, fields ->
        {node, fields}
    end)
    |> elem(1)
  end

  defp function_body!(ast, function_name) do
    {_ast, body} =
      Macro.prewalk(ast, nil, fn
        {:defp, _meta, [{^function_name, _call_meta, _args}, [do: body]]} = node, nil ->
          {node, body}

        node, found ->
          {node, found}
      end)

    body || flunk("missing private function #{function_name}")
  end

  defp aliases_in(file) do
    file
    |> parsed!()
    |> Macro.prewalk([], fn
      {:__aliases__, _meta, parts} = node, aliases -> {node, [parts | aliases]}
      node, aliases -> {node, aliases}
    end)
    |> elem(1)
  end

  defp repo_calls_in(file) do
    file
    |> parsed!()
    |> Macro.prewalk([], fn
      {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Repo]}, function]}, _meta, _args} = node,
      calls ->
        {node, [{file, function} | calls]}

      node, calls ->
        {node, calls}
    end)
    |> elem(1)
  end

  defp fragment_calls_in(file) do
    file
    |> parsed!()
    |> Macro.prewalk([], fn
      {:fragment, meta, [sql | _arguments]} = node, fragments ->
        {node, [%{file: file, sql: sql, line: meta[:line]} | fragments]}

      node, fragments ->
        {node, fragments}
    end)
    |> elem(1)
  end

  defp dynamic_sources_in(file) do
    file
    |> parsed!()
    |> Macro.prewalk([], fn
      {:from, _meta, [{:in, _in_meta, [_binding, source]} | _arguments]} = node,
      dynamic_sources ->
        if fixed_source?(source),
          do: {node, dynamic_sources},
          else: {node, [Macro.to_string(source) | dynamic_sources]}

      {:join, _meta, arguments} = node, dynamic_sources ->
        sources =
          for {:in, _in_meta, [_binding, source]} <- arguments,
              not fixed_source?(source),
              do: Macro.to_string(source)

        {node, sources ++ dynamic_sources}

      node, dynamic_sources ->
        {node, dynamic_sources}
    end)
    |> elem(1)
  end

  defp fixed_source?(source) when is_binary(source), do: true

  defp fixed_source?({{:., _dot_meta, [_receiver, :scope_query]}, _meta, [source | _arguments]})
       when is_binary(source),
       do: true

  defp fixed_source?(_source), do: false

  defp parsed!(file) do
    file
    |> File.read!()
    |> Code.string_to_quoted!(file: file, columns: true, token_metadata: true)
  end
end
