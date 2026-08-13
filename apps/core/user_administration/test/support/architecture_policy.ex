defmodule Bilimbi.Core.UserAdministration.ArchitecturePolicy do
  @moduledoc false

  @query_module Bilimbi.Core.UserAdministration.Query
  @repo_module [:Bilimbi, :Base, :Repo]
  @ecto_query_module [:Ecto, :Query]
  @forbidden_owner_modules [
    [:Bilimbi, :Core, :User, :Schema],
    [:Bilimbi, :Core, :Company, :Schema],
    [:Bilimbi, :Base, :Authz, :PrincipalRole],
    [:Bilimbi, :Base, :Authz, :Role]
  ]

  @approved_source_sites [
    {:final_query, :from, :total, {:literal, "user_total"}, 34},
    {:final_query, :left_join, :user, {:literal, "page_users"}, 35},
    {:final_query, :left_join, :roles, {:literal, "page_roles"}, 37},
    {:tenant_companies, :from, :company, {:scope_query, "companies", :scope}, 68},
    {:live_companies, :from, :company, {:literal, "tenant_companies"}, 79},
    {:visible_role_assignments, :from, :assignment, {:literal, "base_authz_principal_roles"}, 88},
    {:visible_role_assignments, :join, :role, {:literal, "base_authz_roles"}, 89},
    {:visible_role_assignments, :left_join, :assignment_company, {:literal, "live_companies"},
     91},
    {:visible_role_assignments, :left_join, :role_company, {:literal, "live_companies"}, 93},
    {:filtered_users, :from, :user, {:literal, "users"}, 130},
    {:filtered_users, :join, :company, {:literal, "tenant_companies"}, 132},
    {:role_filter, :join, :assignment, {:literal, "visible_role_assignments"}, 159},
    {:user_total, :from, :user, {:literal, "filtered_users"}, 166},
    {:page_users, :from, :user, {:literal, "filtered_users"}, 172},
    {:page_role_rows, :from, :user, {:literal, "page_users"}, 189},
    {:page_role_rows, :join, :role, {:literal, "visible_role_assignments"}, 190},
    {:page_roles, :from, :role, {:literal, "page_role_rows"}, 204}
  ]

  @approved_fragment_sql "array_agg(? ORDER BY ?, ?, ?)"
  @approved_fragment_sites [
    {:page_roles, 209, [:role_id, :role_name, :role_code, :role_id]},
    {:page_roles, 217, [:role_name, :role_name, :role_code, :role_id]},
    {:page_roles, 225, [:role_code, :role_name, :role_code, :role_id]},
    {:page_roles, 233, [:role_is_system, :role_name, :role_code, :role_id]}
  ]

  @physical_bindings %{
    "companies" => {:tenant_companies, :company},
    "users" => {:filtered_users, :user},
    "base_authz_principal_roles" => {:visible_role_assignments, :assignment},
    "base_authz_roles" => {:visible_role_assignments, :role}
  }

  @spec validate_files([Path.t()], [map()], Path.t()) :: [String.t()]
  def validate_files(files, manifest, query_file) do
    query_file = normalize_path(query_file)
    analyses = Enum.map(files, &analyze_file/1)

    analyses
    |> Enum.flat_map(&validate_analysis(&1, query_file))
    |> Kernel.++(validate_sources(analyses, manifest, query_file))
    |> Kernel.++(validate_fields(analyses, manifest, query_file))
    |> Kernel.++(validate_fragments(analyses, query_file))
  end

  @spec validate_source(String.t(), Path.t(), [map()], Path.t()) :: [String.t()]
  def validate_source(source, file, manifest, query_file) do
    file = normalize_path(file)
    analysis = analyze(source, file)
    query_file = normalize_path(query_file)

    validate_analysis(analysis, query_file) ++
      validate_sources([analysis], manifest, query_file, complete?: false) ++
      validate_fragments([analysis], query_file, complete?: false)
  end

  @spec source_sites([Path.t()]) :: [map()]
  def source_sites(files), do: files |> Enum.map(&analyze_file/1) |> Enum.flat_map(& &1.sources)

  @spec fragment_sites([Path.t()]) :: [map()]
  def fragment_sites(files),
    do: files |> Enum.map(&analyze_file/1) |> Enum.flat_map(& &1.fragments)

  defp analyze_file(file), do: file |> File.read!() |> analyze(normalize_path(file))

  defp analyze(source, file) do
    ast = Code.string_to_quoted!(source, file: file, columns: true, token_metadata: true)

    modules =
      ast
      |> collect_modules()
      |> Enum.map(&analyze_module(&1, file))

    %{
      file: file,
      modules: Enum.map(modules, & &1.module),
      aliases: Enum.flat_map(modules, & &1.aliases),
      imports: Enum.flat_map(modules, & &1.imports),
      delegates: Enum.flat_map(modules, & &1.delegates),
      module_references: Enum.flat_map(modules, & &1.module_references),
      repo_calls: Enum.flat_map(modules, & &1.repo_calls),
      sources: Enum.flat_map(modules, & &1.sources),
      fragments: Enum.flat_map(modules, & &1.fragments),
      function_bodies: Enum.flat_map(modules, & &1.function_bodies)
    }
  end

  defp collect_modules(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, meta, [name, [do: body]]} = node, modules ->
          module = module_name(name)
          {node, [%{module: module, meta: meta, body: body} | modules]}

        node, modules ->
          {node, modules}
      end)

    Enum.reverse(modules)
  end

  defp analyze_module(%{module: module, body: body}, file) do
    aliases = aliases(body, module, file)
    repo_aliases = repo_aliases(aliases)
    forms = block_forms(body)

    function_bodies =
      for form <- forms,
          {visibility, name, meta, function_body} <- [function(form)],
          not is_nil(name),
          do: %{
            module: module,
            visibility: visibility,
            name: name,
            meta: meta,
            ast: function_body
          }

    contexts =
      Enum.map(function_bodies, &%{module: module, function: &1.name, ast: &1.ast}) ++
        for form <- forms,
            is_nil(elem(function(form), 1)),
            do: %{module: module, function: nil, ast: form}

    %{
      module: module,
      aliases: aliases,
      imports: directives(body, [:import, :require, :use], module, file),
      delegates: delegates(body, module, file, repo_aliases),
      module_references: module_references(body, module, file),
      repo_calls: Enum.flat_map(contexts, &repo_calls(&1, file, repo_aliases)),
      sources: Enum.flat_map(contexts, &source_sites(&1, file)),
      fragments: Enum.flat_map(contexts, &fragment_sites(&1, file)),
      function_bodies: function_bodies
    }
  end

  defp aliases(ast, module, file) do
    {_ast, aliases} =
      Macro.prewalk(ast, [], fn
        {:alias, meta, [target | options]} = node, aliases ->
          parts = module_parts(target)
          as = options |> List.first() |> keyword_value(:as) |> module_parts()
          name = if as == [], do: List.last(parts), else: List.last(as)

          alias_info = %{module: module, file: file, target: parts, as: name, meta: meta}
          {node, [alias_info | aliases]}

        node, aliases ->
          {node, aliases}
      end)

    Enum.reverse(aliases)
  end

  defp directives(ast, directive_names, module, file) do
    {_ast, directives} =
      Macro.prewalk(ast, [], fn
        {name, meta, [target | _options]} = node, directives ->
          if name in directive_names do
            {node,
             [
               %{
                 module: module,
                 file: file,
                 directive: name,
                 target: module_parts(target),
                 meta: meta
               }
               | directives
             ]}
          else
            {node, directives}
          end

        node, directives ->
          {node, directives}
      end)

    Enum.reverse(directives)
  end

  defp delegates(ast, module, file, repo_aliases) do
    {_ast, delegates} =
      Macro.prewalk(ast, [], fn
        {:defdelegate, meta, [_head, options]} = node, delegates when is_list(options) ->
          target = keyword_value(options, :to)
          target_parts = resolve_module(target, repo_aliases)

          {node, [%{module: module, file: file, target: target_parts, meta: meta} | delegates]}

        node, delegates ->
          {node, delegates}
      end)

    Enum.reverse(delegates)
  end

  defp module_references(ast, module, file) do
    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, meta, parts} = node, references ->
          {node, [%{module: module, file: file, target: parts, meta: meta} | references]}

        node, references ->
          {node, references}
      end)

    Enum.reverse(references)
  end

  defp repo_calls(context, file, repo_aliases) do
    {_ast, calls} =
      Macro.prewalk(context.ast, [], fn
        {{:., _dot_meta, [receiver, function]}, meta, args} = node, calls
        when is_atom(function) ->
          case resolve_module(receiver, repo_aliases) do
            @repo_module ->
              call = %{
                module: context.module,
                function_context: context.function,
                function: function,
                args: args,
                receiver: module_parts(receiver),
                file: file,
                meta: meta
              }

              {node, [call | calls]}

            _other ->
              {node, calls}
          end

        node, calls ->
          {node, calls}
      end)

    Enum.reverse(calls)
  end

  defp source_sites(context, file) do
    {_ast, sites} =
      Macro.prewalk(context.ast, [], fn
        {:from, meta, arguments} = node, sites ->
          {node, sources_from(:from, meta, arguments, context, file) ++ sites}

        {{:., _dot_meta, [receiver, :from]}, meta, arguments} = node, sites ->
          if module_parts(receiver) == @ecto_query_module do
            {node, sources_from(:from, meta, arguments, context, file) ++ sites}
          else
            {node, sites}
          end

        {:join, meta, arguments} = node, sites ->
          {node, sources_from(:join, meta, arguments, context, file) ++ sites}

        {{:., _dot_meta, [receiver, :join]}, meta, arguments} = node, sites ->
          if module_parts(receiver) == @ecto_query_module do
            {node, sources_from(:join, meta, arguments, context, file) ++ sites}
          else
            {node, sites}
          end

        node, sites ->
          {node, sites}
      end)

    Enum.reverse(sites)
  end

  defp sources_from(:from, meta, [source | arguments], context, file) do
    primary = source_site(:from, source, meta, context, file)

    joins =
      arguments
      |> List.first()
      |> List.wrap()
      |> Enum.flat_map(fn
        {join_kind, source} when join_kind in [:join, :left_join, :right_join, :full_join] ->
          [source_site(join_kind, source, ast_meta(source), context, file)]

        _other ->
          []
      end)

    [primary | joins]
  end

  defp sources_from(:join, meta, arguments, context, file) do
    case Enum.find(arguments, &match?({:in, _, _}, &1)) do
      nil -> [source_site(:join, :missing_source, meta, context, file)]
      source -> [source_site(:join, source, ast_meta(source), context, file)]
    end
  end

  defp source_site(kind, {:in, meta, [binding, source]}, fallback_meta, context, file) do
    %{
      module: context.module,
      function: context.function,
      kind: kind,
      binding: variable_name(binding),
      source: normalize_source(source),
      file: file,
      meta: if(meta == [], do: fallback_meta, else: meta)
    }
  end

  defp source_site(kind, source, meta, context, file) do
    %{
      module: context.module,
      function: context.function,
      kind: kind,
      binding: nil,
      source: {:dynamic, Macro.to_string(source)},
      file: file,
      meta: meta
    }
  end

  defp fragment_sites(context, file) do
    {_ast, sites} =
      Macro.prewalk(context.ast, [], fn
        {:fragment, meta, arguments} = node, sites ->
          {node, [fragment_site(arguments, meta, context, file) | sites]}

        {{:., _dot_meta, [receiver, :fragment]}, meta, arguments} = node, sites ->
          if module_parts(receiver) == @ecto_query_module do
            {node, [fragment_site(arguments, meta, context, file) | sites]}
          else
            {node, sites}
          end

        node, sites ->
          {node, sites}
      end)

    Enum.reverse(sites)
  end

  defp fragment_site([sql | arguments], meta, context, file) do
    %{
      module: context.module,
      function: context.function,
      sql: sql,
      arguments: Enum.map(arguments, &normalize_fragment_argument/1),
      file: file,
      meta: meta
    }
  end

  defp fragment_site(arguments, meta, context, file) do
    %{
      module: context.module,
      function: context.function,
      sql: :missing,
      arguments: Enum.map(arguments, &{:other, Macro.to_string(&1)}),
      file: file,
      meta: meta
    }
  end

  defp validate_analysis(analysis, query_file) do
    alias_violations =
      Enum.flat_map(analysis.aliases, fn alias_info ->
        cond do
          alias_info.target == @repo_module and
              not (analysis.file == query_file and alias_info.module == @query_module and
                       alias_info.as == :Repo) ->
            [violation(alias_info, "Repo alias is outside the approved Query alias")]

          alias_info.target == @ecto_query_module ->
            [violation(alias_info, "aliasing Ecto.Query is forbidden")]

          true ->
            []
        end
      end)

    directive_violations =
      Enum.flat_map(analysis.imports, fn directive ->
        cond do
          directive.target == @repo_module ->
            [violation(directive, "Repo import/require/use is forbidden")]

          directive.target == @ecto_query_module and
              not (analysis.file == query_file and directive.module == @query_module and
                       directive.directive == :import) ->
            [violation(directive, "Ecto.Query may only be imported by the private Query")]

          true ->
            []
        end
      end)

    delegate_violations =
      for delegate <- analysis.delegates,
          delegate.target == @repo_module,
          do: violation(delegate, "delegating to Repo is forbidden")

    owner_violations =
      for reference <- analysis.module_references,
          reference.target in @forbidden_owner_modules,
          do: violation(reference, "owner schema/query module reference is forbidden")

    repo_reference_violations =
      for reference <- analysis.module_references,
          reference.target == @repo_module,
          not approved_repo_reference?(reference, query_file),
          do: violation(reference, "Repo module reference is outside its exact Query alias site")

    repo_violations =
      Enum.flat_map(analysis.repo_calls, fn call ->
        if approved_repo_call?(call, query_file) do
          []
        else
          [violation(call, "Repo call is outside exact Query Repo.all(query) site")]
        end
      end)

    query_builder_violations =
      for reference <- analysis.module_references,
          reference.target == @ecto_query_module,
          not approved_ecto_query_reference?(reference, query_file),
          do: violation(reference, "Ecto.Query reference is outside the private Query")

    alias_violations ++
      directive_violations ++
      delegate_violations ++
      owner_violations ++
      repo_reference_violations ++ repo_violations ++ query_builder_violations
  end

  defp validate_sources(analyses, manifest, query_file, options \\ []) do
    complete? = Keyword.get(options, :complete?, true)
    sources = Enum.flat_map(analyses, & &1.sources)

    unexpected =
      for site <- sources,
          source_signature(site) not in @approved_source_sites or site.file != query_file or
            site.module != @query_module,
          do: violation(site, "unapproved or dynamic Ecto source: #{inspect(site.source)}")

    missing =
      if complete? do
        actual = Enum.map(sources, &source_signature/1)

        for expected <- @approved_source_sites,
            Enum.count(actual, &(&1 == expected)) != 1,
            do: "approved Query source site missing or duplicated: #{inspect(expected)}"
      else
        []
      end

    manifest_relations = MapSet.new(manifest, & &1.relation)

    actual_physical_relations =
      sources
      |> Enum.flat_map(fn site ->
        case site.source do
          {:literal, relation} ->
            if MapSet.member?(manifest_relations, relation), do: [relation], else: []

          {:scope_query, relation, :scope} ->
            if MapSet.member?(manifest_relations, relation), do: [relation], else: []

          _other ->
            []
        end
      end)

    physical_violations =
      if complete? and
           Enum.frequencies(actual_physical_relations) !=
             Map.new(manifest_relations, &{&1, 1}) do
        ["physical Query sources do not equal ConsumedRelations.manifest/0 exactly once"]
      else
        []
      end

    unexpected ++ missing ++ physical_violations
  end

  defp validate_fields(analyses, manifest, query_file) do
    query = Enum.find(analyses, &(&1.file == query_file))
    manifest_by_relation = Map.new(manifest, &{&1.relation, &1})

    cond do
      is_nil(query) ->
        ["approved Query file was not scanned"]

      MapSet.new(Map.keys(manifest_by_relation)) != MapSet.new(Map.keys(@physical_bindings)) ->
        ["ConsumedRelations.manifest/0 relations do not match reviewed physical bindings"]

      true ->
        Enum.flat_map(@physical_bindings, fn {relation, {function, binding}} ->
          expected =
            manifest_by_relation
            |> Map.fetch!(relation)
            |> Map.fetch!(:columns)
            |> Map.keys()
            |> Enum.map(&String.to_existing_atom/1)
            |> MapSet.new()

          actual = fields_in(query.function_bodies, function, binding)

          if actual == expected,
            do: [],
            else: [
              "#{function}/#{binding} fields #{inspect(actual)} do not equal manifest #{inspect(expected)}"
            ]
        end)
    end
  end

  defp validate_fragments(analyses, query_file, options \\ []) do
    complete? = Keyword.get(options, :complete?, true)
    fragments = Enum.flat_map(analyses, & &1.fragments)

    unexpected =
      for site <- fragments,
          fragment_signature(site) not in @approved_fragment_sites or site.file != query_file or
            site.module != @query_module or site.sql != @approved_fragment_sql,
          do: violation(site, "unapproved fragment SQL, arguments, or source position")

    missing =
      if complete? do
        actual = Enum.map(fragments, &fragment_signature/1)

        for expected <- @approved_fragment_sites,
            Enum.count(actual, &(&1 == expected)) != 1,
            do: "approved Query fragment site missing or duplicated: #{inspect(expected)}"
      else
        []
      end

    unexpected ++ missing
  end

  defp fields_in(function_bodies, function, binding) do
    function_bodies
    |> Enum.filter(&(&1.module == @query_module and &1.name == function))
    |> Enum.map(& &1.ast)
    |> Enum.reduce(MapSet.new(), fn ast, fields ->
      {_ast, found} =
        Macro.prewalk(ast, fields, fn
          {{:., _dot_meta, [{^binding, _binding_meta, _context}, field]}, _meta, []} = node, found
          when is_atom(field) ->
            {node, MapSet.put(found, field)}

          node, found ->
            {node, found}
        end)

      found
    end)
  end

  defp approved_repo_call?(call, query_file) do
    call.file == query_file and call.module == @query_module and call.function_context == :list and
      call.function == :all and call.receiver == [:Repo] and call.meta[:line] == 19 and
      call.meta[:column] > 0 and match?([{:query, _, _}], call.args)
  end

  defp approved_repo_reference?(reference, query_file) do
    reference.file == query_file and reference.module == @query_module and
      reference.meta[:line] == 6 and reference.meta[:column] > 0
  end

  defp approved_ecto_query_reference?(reference, query_file) do
    reference.file == query_file and reference.module == @query_module and
      reference.meta[:line] == 4 and reference.meta[:column] > 0
  end

  defp source_signature(site) do
    {site.function, site.kind, site.binding, site.source, site.meta[:line]}
  end

  defp fragment_signature(site) do
    fields =
      Enum.map(site.arguments, fn
        {:field, :role, field} -> field
        other -> other
      end)

    {site.function, site.meta[:line], fields}
  end

  defp normalize_source(source) when is_binary(source), do: {:literal, source}

  defp normalize_source(
         {{:., _dot_meta, [receiver, :scope_query]}, _meta, [relation, {:scope, _, _}]} = source
       )
       when is_binary(relation) do
    if module_parts(receiver) in [[:Tenancy], [:Bilimbi, :Base, :Tenancy]],
      do: {:scope_query, relation, :scope},
      else: {:dynamic, Macro.to_string(source)}
  end

  defp normalize_source(source), do: {:dynamic, Macro.to_string(source)}

  defp normalize_fragment_argument(
         {{:., _dot_meta, [{binding, _binding_meta, _context}, field]}, _meta, []}
       )
       when is_atom(binding) and is_atom(field),
       do: {:field, binding, field}

  defp normalize_fragment_argument(argument), do: {:other, Macro.to_string(argument)}

  defp repo_aliases(aliases) do
    aliases
    |> Enum.filter(&(&1.target == @repo_module))
    |> Map.new(&{&1.as, @repo_module})
  end

  defp resolve_module(ast, aliases) do
    case module_parts(ast) do
      [name] -> Map.get(aliases, name, [name])
      parts -> parts
    end
  end

  defp module_parts({:__aliases__, _meta, parts}), do: parts
  defp module_parts(nil), do: []
  defp module_parts(atom) when is_atom(atom), do: [atom]
  defp module_parts(_other), do: []

  defp module_name(ast), do: ast |> module_parts() |> Module.concat()

  defp keyword_value(options, key) when is_list(options) do
    if Keyword.keyword?(options), do: Keyword.get(options, key), else: nil
  end

  defp keyword_value(_options, _key), do: nil

  defp block_forms({:__block__, _meta, forms}), do: forms
  defp block_forms(form), do: [form]

  defp function({visibility, meta, [head, [do: body]]}) when visibility in [:def, :defp] do
    {name, _head_meta, _arguments} = unwrap_function_head(head)
    {visibility, name, meta, body}
  end

  defp function(_form), do: {nil, nil, nil, nil}

  defp unwrap_function_head({:when, _meta, [head | _guards]}), do: unwrap_function_head(head)

  defp unwrap_function_head({name, meta, arguments}) when is_atom(name),
    do: {name, meta, arguments}

  defp variable_name({name, _meta, context}) when is_atom(name) and is_atom(context), do: name
  defp variable_name(_other), do: nil

  defp ast_meta({_name, meta, _arguments}) when is_list(meta), do: meta
  defp ast_meta(_ast), do: []

  defp violation(site, message) do
    "#{message} at #{site.file}:#{site.meta[:line] || 0}:#{site.meta[:column] || 0}"
  end

  defp normalize_path(path), do: path |> Path.expand() |> String.downcase()
end
