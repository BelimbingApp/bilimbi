defmodule BilimbiWeb.TenantScopeGateTest do
  @moduledoc """
  Fails the build when module code queries a tenant-owned table without
  starting from `Bilimbi.Base.Tenancy.scope_query/2`.

  `scope_query/2` has one clause, so a missing tenant crashes rather than
  returning every tenant's rows. That only protects a query that calls it. A
  function's name and arity say nothing about the `WHERE` clause inside, so the
  gate reads the code that builds the query.

  A table is tenant-owned when an installed module's schema contract declares a
  `tenant_id` column for it, or when an installed Ecto schema maps a `tenant_id`
  field (a Bilimbi-only contract may leave its table out of `tables/0` until it
  is migrated). Nothing here is a hand list of tables.

  A tenant-owned schema, or a string source naming a tenant-owned table, may
  appear in module `lib/` code only as:

    * the first argument of `scope_query/2`;
    * the receiver of a call (`Schema.changeset/2`, `Schema.__schema__/1`);
    * a struct literal or pattern (`%Schema{}`);
    * inside a typespec, `alias`, `import`, `use`, `require` or docs.

  Anything else, such as `from x in Schema`, `Repo.get(Schema, id)` or
  `Schema |> where(...)`, is an unscoped read and fails here.

  `@allowed` is the explicit, reviewed list of exceptions. Each entry names the
  file, the enclosing function and the schema, and carries the reason it may
  read across tenants. Adding an entry is a review decision, made in the same
  change as the code it excuses; a stale entry fails too, so the list cannot
  outlive the code it was written for. Raw SQL through `Ecto.Adapters.SQL` is
  outside this gate; AGENTS.md section 13 treats it as a review defect.
  """

  use ExUnit.Case, async: true

  alias Bilimbi.Base.ModuleRegistry
  alias Bilimbi.Base.ModuleRegistry.MixDiscovery

  @workspace_root Path.expand("../../../..", __DIR__)

  # {path relative to the workspace root, "function/arity", schema or table}
  # => the reason this read may span tenants.
  @allowed %{
    {"apps/core/user/lib/user/admin_bootstrap.ex", "run/1",
     "Bilimbi.Core.User.BootstrapReceipt"} =>
      "The owner reads one global installation receipt before a tenant exists; its tenant_id is historical attribution, not tenancy ownership. The trusted bootstrap exposes only completion status and preserves revoked access.",
    {"apps/base/workflow/lib/workflow/coordination.ex", "append_event/6",
     "Bilimbi.Base.Workflow.EventSchema"} =>
      "Appends to a run the caller's scoped read already proved; the sequence is that run's, keyed by run id.",
    {"apps/base/workflow/lib/workflow/coordination.ex", "graph/4",
     "Bilimbi.Base.Workflow.DependencySchema"} =>
      "Owner-local invariant proof over one proved run's children; it must see a contradictory tenant row a scoped read would hide.",
    {"apps/base/workflow/lib/workflow/coordination.ex", "graph/4",
     "Bilimbi.Base.Workflow.EventSchema"} =>
      "Owner-local invariant proof over one proved run's children; it must see a contradictory tenant row a scoped read would hide.",
    {"apps/base/workflow/lib/workflow/coordination.ex", "graph/4",
     "Bilimbi.Base.Workflow.WorkSchema"} =>
      "Owner-local invariant proof over one proved run's children; it must see a contradictory tenant row a scoped read would hide.",
    {"apps/base/workflow/lib/workflow/engine.ex", "bind/2", "Bilimbi.Base.Workflow.BindingSchema"} =>
      "Global (flow, flow_id) uniqueness proof: a scoped miss must never let a legacy subject be rebound to another tenant.",
    {"apps/core/company/lib/company.ex", "fetch_tenant_id_for_company/1",
     "Bilimbi.Core.Company.Schema"} =>
      "Derives the tenant a company belongs to, so the caller can build its scope; there is no scope yet to apply.",
    {"apps/core/company/lib/company/administration_index.ex", "base_query/1",
     "Bilimbi.Core.Company.Schema"} =>
      "Parent join hangs off the scope_query base; composite FK companies_parent_tenant_foreign keeps it in the same tenant.",
    {"apps/core/company/lib/company/administration_index.ex", "base_query/1",
     "tenant_primary_companies"} =>
      "Primary join hangs off the scope_query base; company_id is UNIQUE there, so a match implies the company's tenant.",
    {"apps/core/company/lib/company/primary_company_manager.ex", "assignment_exists?/1",
     "Bilimbi.Core.Company.TenantPrimaryCompany"} =>
      "Owner-module invariant check bounded to the tenant being reconciled.",
    {"apps/core/company/lib/company/primary_company_manager.ex", "find_for_resolved_tenant/1",
     "Bilimbi.Core.Company.TenantPrimaryCompany"} =>
      "Join onto the scope_query base whose ON clause pins assignment.tenant_id to the company's tenant.",
    {"apps/core/company/lib/company/primary_company_manager.ex", "lock_company!/1",
     "Bilimbi.Core.Company.Schema"} =>
      "Owner-module row lock by company id; the caller validates the owner tenant afterwards.",
    {"apps/core/company/lib/company/primary_company_manager.ex", "locked_assignment/1",
     "Bilimbi.Core.Company.TenantPrimaryCompany"} =>
      "Owner-module row lock bounded to the tenant being reconciled.",
    {"apps/core/company/lib/company/primary_company_manager.ex", "validate_company_available!/2",
     "Bilimbi.Core.Company.TenantPrimaryCompany"} =>
      "Deliberate cross-tenant uniqueness proof: a company may be primary for only one tenant.",
    {"apps/core/company/lib/company/reference_types.ex", "delete_legal_entity_type/2",
     "Bilimbi.Core.Company.Schema"} =>
      "Legal entity types are shared reference data; deleting one must see every tenant's companies that use it."
  }

  @doc_attributes [:doc, :moduledoc, :typedoc, :spec, :type, :typep, :opaque, :callback]
  @module_directives [:alias, :import, :require, :use]

  test "every query over a tenant-owned table starts from Tenancy.scope_query/2" do
    tenant_owned = tenant_owned_sources()

    violations =
      workspace_files()
      |> Enum.flat_map(&violations_in_file(&1, tenant_owned))
      |> Enum.sort()

    unexpected = Enum.reject(violations, &Map.has_key?(@allowed, &1))
    stale = @allowed |> Map.keys() |> Enum.reject(&(&1 in violations)) |> Enum.sort()

    assert unexpected == [], unexpected_message(unexpected)
    assert stale == [], stale_message(stale)
  end

  test "tenant-owned tables come from the installed contracts and schemas" do
    %{schemas: schemas, tables: tables} = tenant_owned_sources()

    assert "companies" in tables
    assert "addresses" in tables
    assert Bilimbi.Core.Company.Schema in schemas
    assert Bilimbi.Base.Artifacts.Schema in schemas
    refute "tenants" in tables
    refute "users" in tables
  end

  describe "the scanner" do
    setup do
      {:ok, owned: %{schemas: MapSet.new([Fixture.Schema]), tables: MapSet.new(["things"])}}
    end

    test "accepts a read that begins with scope_query/2", %{owned: owned} do
      source = """
      defmodule Fixture.Reads do
        alias Fixture.Schema
        alias Bilimbi.Base.Tenancy
        alias Bilimbi.Base.Repo

        def list(scope), do: Repo.all(from(r in Tenancy.scope_query(Schema, scope), select: r.id))
        def table(scope), do: Tenancy.scope_query("things", scope)
      end
      """

      assert scan(source, owned) == []
    end

    test "accepts receivers, struct literals and typespecs", %{owned: owned} do
      source = """
      defmodule Fixture.Writes do
        alias Fixture.Schema

        @spec build(map()) :: Schema.t() | %Schema{}
        def build(attrs), do: %Schema{} |> Schema.changeset(attrs)
        def match?(%Schema{}), do: true
      end
      """

      assert scan(source, owned) == []
    end

    test "flags each shape of unscoped read", %{owned: owned} do
      source = """
      defmodule Fixture.Reads do
        alias Fixture.Schema, as: Thing
        alias Bilimbi.Base.Repo

        def from_clause, do: from(r in Thing, select: r.id)
        def join_clause(q), do: join(q, :left, [r], t in Thing, on: true)
        def get(id), do: Repo.get(Thing, id)
        def piped, do: Thing |> where([t], t.id > 1)
        def table, do: from(r in "things", select: r.id)
        def qualified, do: from(r in Fixture.Schema, select: r.id)
      end
      """

      assert scan(source, owned) |> Enum.map(&elem(&1, 1)) == [
               "from_clause/0",
               "join_clause/1",
               "get/1",
               "piped/0",
               "table/0",
               "qualified/0"
             ]
    end

    test "flags a query hidden in a multi-clause or private function", %{owned: owned} do
      source = """
      defmodule Fixture.Reads do
        alias Fixture.Schema

        def run(scope), do: private(scope)
        defp private(_scope), do: from(r in Schema)
      end
      """

      assert [{_path, "private/1", "Fixture.Schema"}] = scan(source, owned)
    end
  end

  defp scan(source, owned) do
    source |> Code.string_to_quoted!(columns: false) |> violations("fixture.ex", owned)
  end

  # --- discovery ---------------------------------------------------------

  defp tenant_owned_sources do
    modules = ModuleRegistry.installed_modules!()

    contract_tables =
      for module <- modules,
          contract = module.schema_contract,
          not is_nil(contract),
          spec <- contract.tables(),
          Map.has_key?(spec.columns, "tenant_id"),
          into: MapSet.new(),
          do: spec.name

    schemas =
      for module <- modules,
          mod <- Application.spec(module.otp_app, :modules) || [],
          Code.ensure_loaded?(mod),
          function_exported?(mod, :__schema__, 1),
          source = mod.__schema__(:source),
          is_binary(source),
          source in contract_tables or :tenant_id in mod.__schema__(:fields),
          into: MapSet.new(),
          do: mod

    tables =
      Enum.reduce(schemas, contract_tables, &MapSet.put(&2, &1.__schema__(:source)))

    %{schemas: schemas, tables: tables}
  end

  defp workspace_files do
    MixDiscovery.module_source_files(@workspace_root, "lib/**/*.ex")
  end

  # --- scanning ----------------------------------------------------------

  defp violations_in_file(path, owned) do
    relative = Path.relative_to(path, @workspace_root)
    path |> File.read!() |> Code.string_to_quoted!(file: path) |> violations(relative, owned)
  end

  defp violations(ast, relative, owned) do
    state = %{aliases: %{}, function: "module", owned: owned, found: []}

    {_node, state} = walk(ast, state)

    state.found |> Enum.reverse() |> Enum.map(fn {fun, name} -> {relative, fun, name} end)
  end

  # A node that is not a query source: nothing under it counts.
  defp walk({:@, _, [{attr, _, _}]} = node, state) when attr in @doc_attributes,
    do: {node, state}

  defp walk({directive, _, _} = node, state) when directive in @module_directives do
    {node, record_alias(node, state)}
  end

  defp walk({:%, _, _} = node, state), do: {node, state}

  defp walk({:defmodule, meta, [name, [do: body]]}, state) do
    {_, inner} = walk(body, %{state | aliases: state.aliases})
    {{:defmodule, meta, [name, [do: body]]}, %{state | found: inner.found}}
  end

  defp walk({kind, _, [head | _]} = node, state) when kind in [:def, :defp] do
    {_, inner} = walk_definition(node, head, state)
    {node, %{state | found: inner.found}}
  end

  # scope_query/2 owns its first argument; the scope and the rest are walked.
  defp walk({{:., _, [_receiver, :scope_query]}, _, [_source | rest]} = node, state) do
    {_, state} = walk_list(rest, state)
    {node, state}
  end

  defp walk({:scope_query, _, [_source | rest]} = node, state) do
    {_, state} = walk_list(rest, state)
    {node, state}
  end

  defp walk({{:., _, [{:__aliases__, _, _} = repo, fun]}, _, [source | rest]} = node, state)
       when fun in [:get, :get!, :get_by, :get_by!, :one, :one!, :all, :aggregate, :exists?] do
    state = if repo_alias?(repo), do: check_source(source, state), else: state
    {_, state} = walk_list(rest, state)
    {node, state}
  end

  # A remote call's receiver is a module, not a query source.
  defp walk({{:., _, [receiver, _fun]}, _, args} = node, state) do
    state =
      if match?({:__aliases__, _, _}, receiver), do: state, else: elem(walk(receiver, state), 1)

    {_, state} = walk_list(args, state)
    {node, state}
  end

  defp walk({:is_struct, _, [value | _]} = node, state) do
    {_, state} = walk(value, state)
    {node, state}
  end

  defp walk({:in, _, [binding, source]} = node, state) do
    {_, state} = walk(binding, state)
    {node, check_source(source, state)}
  end

  # `Schema |> Tenancy.scope_query(scope)` is the piped form of the same call.
  defp walk({:|>, _, [left, right]} = node, state) do
    state = if scope_query_call?(right), do: state, else: check_source(left, state)
    {_, state} = walk(right, state)
    {node, state}
  end

  defp walk({:from, _, [source | rest]} = node, state) do
    {_, state} = walk_list(rest, check_source(source, state))
    {node, state}
  end

  defp walk({_form, _meta, args} = node, state) when is_list(args) do
    {_, state} = walk_list(args, state)
    {node, state}
  end

  defp walk({left, right}, state) do
    {_, state} = walk_list([left, right], state)
    {{left, right}, state}
  end

  defp walk(list, state) when is_list(list), do: walk_list(list, state)
  defp walk(node, state), do: {node, state}

  defp walk_list(nodes, state) do
    state = Enum.reduce(nodes, state, fn node, acc -> elem(walk(node, acc), 1) end)
    {nodes, state}
  end

  defp walk_definition(node, head, state) do
    {name, arity} = function_identity(head)
    state = %{state | function: "#{function_name(name)}/#{arity}"}
    {_form, _meta, [_head | body]} = node
    walk_list(body, state)
  end

  defp function_name(name) when is_atom(name), do: Atom.to_string(name)
  defp function_name(name), do: Macro.to_string(name)

  defp function_identity({:when, _, [head | _]}), do: function_identity(head)
  defp function_identity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp function_identity({name, _, _}), do: {name, 0}

  defp scope_query_call?({{:., _, [_receiver, :scope_query]}, _, _}), do: true
  defp scope_query_call?({:scope_query, _, _}), do: true
  defp scope_query_call?(_other), do: false

  defp repo_alias?({:__aliases__, _, parts}), do: List.last(parts) == :Repo

  # `from(x in Source)` is handled by the `in` clause; a bare source is checked
  # here. A source that is not an alias or a literal (a variable, a call, a
  # nested query) is left to the walk of its own children.
  defp check_source({:__aliases__, _, _} = ref, state) do
    case resolve(ref, state.aliases) do
      module ->
        if MapSet.member?(state.owned.schemas, module),
          do: found(state, inspect(module)),
          else: state
    end
  end

  defp check_source(table, state) when is_binary(table) do
    if MapSet.member?(state.owned.tables, table), do: found(state, table), else: state
  end

  defp check_source(other, state), do: elem(walk(other, state), 1)

  defp found(state, name), do: %{state | found: [{state.function, name} | state.found]}

  # --- alias resolution --------------------------------------------------

  defp record_alias({:alias, _, [{:__aliases__, _, parts}]}, state),
    do: put_alias(state, List.last(parts), Module.concat(parts))

  defp record_alias({:alias, _, [{:__aliases__, _, parts}, opts]}, state) when is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, [as]} -> put_alias(state, as, Module.concat(parts))
      _ -> state
    end
  end

  defp record_alias(
         {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]},
         state
       ) do
    Enum.reduce(children, state, fn {:__aliases__, _, parts}, acc ->
      put_alias(acc, List.last(parts), Module.concat(base ++ parts))
    end)
  end

  defp record_alias(_other, state), do: state

  defp put_alias(state, name, module),
    do: %{state | aliases: Map.put(state.aliases, name, module)}

  defp resolve({:__aliases__, _, [head | tail] = parts}, aliases) do
    case Map.fetch(aliases, head) do
      {:ok, module} -> Module.concat([module | tail])
      :error -> Module.concat(parts)
    end
  end

  # --- messages ----------------------------------------------------------

  defp unexpected_message(unexpected) do
    lines =
      Enum.map_join(unexpected, "\n", fn {path, fun, name} -> "  #{path} #{fun} reads #{name}" end)

    """
    A tenant-owned table is queried without Tenancy.scope_query/2:
    #{lines}

    Begin the read with `Tenancy.scope_query(Schema, scope)`. If the read must
    span tenants (a platform-wide job, a lock inside the owning module), add the
    {file, function, schema} to @allowed in #{Path.relative_to_cwd(__ENV__.file)}
    with the reason; that is a review decision made in the same change.
    """
  end

  defp stale_message(stale) do
    """
    These @allowed entries match no unscoped read any more; delete them:
    #{Enum.map_join(stale, "\n", &"  #{inspect(&1)}")}
    """
  end
end
