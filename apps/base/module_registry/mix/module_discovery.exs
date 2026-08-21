defmodule Bilimbi.Base.ModuleRegistry.MixDiscovery do
  @moduledoc """
  Discovers, validates, and orders installed Bilimbi deep modules.

  A composition container is a direct child of `apps/` with a
  `bilimbi.container.exs` descriptor. Every immediate directory inside that
  container is an installed module and must contain `bilimbi.module.exs`.
  """

  @container_file "bilimbi.container.exs"
  @module_file "bilimbi.module.exs"
  @layers [:base, :core, :domain, :extension]
  @module_keys [
    :id,
    :kind,
    :layer,
    :required,
    :otp_app,
    :namespace,
    :dependencies,
    :migrations,
    :web,
    :schema_contract,
    :contribution_provider
  ]
  @migration_dispositions [:compatible_baseline, :bilimbi_only]

  @type descriptor :: %{
          optional(:migration_dispositions) => %{
            pos_integer() => :compatible_baseline | :bilimbi_only
          },
          id: String.t(),
          kind: :module,
          layer: :base | :core | :domain | :extension,
          required: boolean(),
          otp_app: atom(),
          namespace: module(),
          dependencies: [String.t()],
          migrations: nil | String.t(),
          web: nil | String.t(),
          schema_contract: nil | module(),
          contribution_provider: nil | module(),
          path: String.t(),
          container_id: String.t()
        }

  @doc """
  OTP apps Phoenix should recompile on the next request in development.

  Nested path packages (`apps/base/ui`, a future Domain, an Extension) are
  not Mix umbrella children, so `reloadable_apps: nil` never sees them.
  This list is the discovered module graph plus the web host, so a builder
  who mounts a module directory gets save-and-refresh without editing
  `config/dev.exs`.
  """
  @spec reloadable_apps(String.t()) :: [atom()]
  def reloadable_apps(workspace_root) do
    workspace_root
    |> discover_workspace!()
    |> Enum.map(& &1.otp_app)
    |> Kernel.++([:web])
  end

  @doc """
  Returns module-owned web integration test directories for the Web host.

  These tests live with the module source but execute in the Web Mix project,
  where the real endpoint, router, authentication hooks, and `ConnCase` are
  available without introducing a forbidden module-to-Web dependency.
  """
  @spec web_test_paths(String.t()) :: [String.t()]
  def web_test_paths(workspace_root) do
    workspace_root
    |> discover_workspace!()
    |> Enum.flat_map(fn descriptor ->
      test_path = Path.join(descriptor.path, "web_test")

      cond do
        not is_binary(descriptor.web) or not File.dir?(test_path) ->
          []

        File.regular?(Path.join(test_path, "test_helper.exs")) ->
          [test_path]

        true ->
          raise ArgumentError,
                "#{descriptor.id} web_test must contain test_helper.exs for the Web test runner"
      end
    end)
  end

  @doc "Returns local path dependencies for modules installed in a container."
  @spec container_dependencies(String.t()) :: [Mix.Project.dependency()]
  def container_dependencies(container_root) do
    container_root = Path.expand(container_root)
    validate_container_root!(container_root)

    container_root
    |> workspace_root!()
    |> discover_workspace!()
    |> Enum.filter(&(&1.container_path == container_root))
    |> Enum.map(fn descriptor ->
      {descriptor.otp_app, path: Path.relative_to(descriptor.path, container_root)}
    end)
  end

  @doc "Returns deterministic module-local test commands for a container."
  @spec container_test_commands(String.t()) :: [String.t()]
  def container_test_commands(container_root) do
    container_root = Path.expand(container_root)
    validate_container_root!(container_root)

    container_root
    |> workspace_root!()
    |> discover_workspace!()
    |> Enum.filter(&(&1.container_path == container_root))
    |> Enum.map(fn descriptor ->
      relative_path = Path.relative_to(descriptor.path, container_root)
      ~s(cmd --cd "#{relative_path}" mix test)
    end)
  end

  @doc """
  Returns deterministic module-local strict-compile commands for a container.

  `mix compile --warnings-as-errors` at the umbrella root does **not** fail on a
  path dependency's warnings: the flag applies to the current project, and path
  deps compile as dependencies. A missing required `attr` therefore printed a
  warning and exited 0, so `required: true` was documentation rather than a gate
  (#176). Compiling each module in its own project context is what makes those
  warnings fatal.
  """
  @spec container_compile_commands(String.t()) :: [String.t()]
  def container_compile_commands(container_root) do
    container_root = Path.expand(container_root)
    validate_container_root!(container_root)

    container_root
    |> workspace_root!()
    |> discover_workspace!()
    |> Enum.filter(&(&1.container_path == container_root))
    |> Enum.map(fn descriptor ->
      relative_path = Path.relative_to(descriptor.path, container_root)
      ~s(cmd --cd "#{relative_path}" mix compile --warnings-as-errors)
    end)
  end

  @doc "Resolves a module's declared dependencies to local Mix path dependencies."
  @spec module_dependencies(String.t()) :: [Mix.Project.dependency()]
  def module_dependencies(module_root) do
    module_root = Path.expand(module_root)
    modules = module_root |> workspace_root!() |> discover_workspace!()
    module = Enum.find(modules, &(&1.path == module_root))

    unless module do
      raise ArgumentError, "#{module_root} is not an installed Bilimbi module"
    end

    dependency_ids = MapSet.new(module.dependencies)

    modules
    |> Enum.filter(&MapSet.member?(dependency_ids, &1.id))
    |> Enum.map(fn dependency ->
      {dependency.otp_app, path: Path.relative_to(dependency.path, module_root)}
    end)
  end

  @doc "Returns application metadata generated from the module descriptor."
  @spec application_env(String.t()) :: keyword()
  def application_env(module_root) do
    module_root = Path.expand(module_root)
    workspace_root = workspace_root!(module_root)
    modules = discover_workspace!(workspace_root)

    order =
      Enum.find_index(modules, &(&1.path == module_root)) ||
        raise(ArgumentError, "#{module_root} is not an installed Bilimbi module")

    descriptor =
      modules
      |> Enum.at(order)
      |> Map.drop([:path, :container_id, :container_layer, :container_path])
      |> Map.put(:order, order)
      |> Map.put(:graph_fingerprint, workspace_fingerprint(workspace_root))

    [bilimbi_module: descriptor]
  end

  @doc "Returns a stable digest of all installed container and module descriptors."
  @spec workspace_fingerprint(String.t()) :: String.t()
  def workspace_fingerprint(path) do
    workspace_root = workspace_root!(path)

    descriptor_files =
      [
        Path.join(workspace_root, "apps/*/#{@container_file}"),
        Path.join(workspace_root, "apps/*/*/#{@module_file}"),
        Path.join(workspace_root, "apps/*/*/priv/web_routes.exs"),
        Path.join(workspace_root, "apps/web/priv/web_routes.exs")
      ]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()

    migration_files =
      workspace_root
      |> discover_workspace!()
      |> Enum.flat_map(fn descriptor ->
        case descriptor.migrations do
          path when is_binary(path) ->
            Path.wildcard(Path.join([descriptor.path, path, "*.exs"]))

          nil ->
            []
        end
      end)

    files = Enum.sort(Enum.uniq(descriptor_files ++ migration_files))

    source =
      Enum.map_join(files, "\0", fn file_path ->
        relative_path = Path.relative_to(file_path, workspace_root)
        relative_path <> "\0" <> File.read!(file_path)
      end)

    :sha256
    |> :crypto.hash(source)
    |> Base.encode16(case: :lower)
  end

  @doc "Stable path of the compile-time route manifest for this workspace."
  @spec route_manifest_path(String.t()) :: String.t()
  def route_manifest_path(workspace_root) do
    # Mix.env/0 returns :prod inside @recursive compilers that compile
    # dependencies, even when the actual build path is _build/dev or _build/test.
    # Derive the environment from Mix.Project.build_path/0 so the manifest always
    # lands in the same _build/<env> directory that DiscoveredRoutes and
    # RouteContract read from.
    env_segment = Path.basename(Mix.Project.build_path())
    Path.join(workspace_root, "_build/#{env_segment}/bilimbi_routes.exs")
  end

  @doc """
  Writes the compile-time route manifest from installed descriptors and the
  optional host route file.

  Reads descriptors from disk. Does not call the runtime registry.
  """
  @spec write_route_manifest!(String.t()) :: :ok
  def write_route_manifest!(workspace_root) do
    workspace_root = Path.expand(workspace_root)
    modules = discover_workspace!(workspace_root)

    module_routes =
      Enum.flat_map(modules, fn descriptor ->
        case descriptor.web do
          path when is_binary(path) ->
            descriptor.path
            |> Path.join(path)
            |> eval_routes!()
            |> Enum.map(&normalize_route!(&1, descriptor.id))

          nil ->
            []
        end
      end)

    host_file = Path.join(workspace_root, "apps/web/priv/web_routes.exs")

    host_routes =
      if File.regular?(host_file) do
        host_file
        |> eval_routes!()
        |> Enum.map(&normalize_route!(&1, "web"))
      else
        []
      end

    contents = inspect(module_routes ++ host_routes, pretty: true, limit: :infinity) <> "\n"
    manifest = route_manifest_path(workspace_root)

    unless File.regular?(manifest) and File.read!(manifest) == contents do
      File.mkdir_p!(Path.dirname(manifest))
      File.write!(manifest, contents)
    end

    :ok
  end

  @doc """
  Contributor IDs Compatibility cannot see at runtime.

  Enumerates from source descriptors, not `Application.loaded_applications/0`.
  Runtime discovery only sees OTP apps in Compatibility's Mix closure, which
  Mix builds from `core/compatibility`'s declared `dependencies`. A module
  with migrations or a `schema_contract` that is missing from that list is
  inert: its migration never runs and its contract is never verified.

  `compatibility_dependencies` overrides the coordinator's declared list so
  tests can prove the guard fails without mutating the live descriptor.
  """
  @spec missing_compatibility_contributors([descriptor()], [String.t()] | nil) :: [String.t()]
  def missing_compatibility_contributors(modules, compatibility_dependencies \\ nil)
      when is_list(modules) do
    dependencies =
      compatibility_dependencies || compatibility_dependencies!(modules)

    closure = MapSet.new(dependencies)

    modules
    |> Enum.filter(&contributor?/1)
    |> Enum.map(& &1.id)
    |> Enum.reject(&(&1 == "core/compatibility" or MapSet.member?(closure, &1)))
    |> Enum.sort()
  end

  defp compatibility_dependencies!(modules) do
    case Enum.find(modules, &(&1.id == "core/compatibility")) do
      nil ->
        raise ArgumentError, "workspace has no core/compatibility coordinator"

      compatibility ->
        compatibility.dependencies
    end
  end

  defp contributor?(module) do
    is_binary(module.migrations) or not is_nil(module.schema_contract)
  end

  @doc "Discovers and validates all installed modules in a source workspace."
  @spec discover_workspace!(String.t()) :: [descriptor()]
  def discover_workspace!(workspace_root) do
    workspace_root = Path.expand(workspace_root)
    apps_root = Path.join(workspace_root, "apps")

    containers =
      apps_root
      |> Path.join("*/#{@container_file}")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&read_container!/1)

    modules = Enum.flat_map(containers, &discover_container_modules!/1)

    modules
    |> validate_unique!(:id, "stable module ID")
    |> validate_unique!(:otp_app, "OTP application ID")
    |> validate_unique_migration_versions!()
    |> validate_container_membership!()
    |> validate_dependencies!()
    |> topological_sort!()
  end

  @doc "Finds a workspace root by walking upward from a path."
  @spec workspace_root!(String.t()) :: String.t()
  def workspace_root!(path) do
    case find_workspace_root(Path.expand(path)) do
      {:ok, root} -> root
      :error -> raise ArgumentError, "could not find Bilimbi workspace above #{path}"
    end
  end

  defp find_workspace_root(path) do
    path = if File.dir?(path), do: path, else: Path.dirname(path)

    cond do
      File.regular?(Path.join(path, "mix.exs")) and File.dir?(Path.join(path, "apps")) ->
        {:ok, path}

      Path.dirname(path) == path ->
        :error

      true ->
        find_workspace_root(Path.dirname(path))
    end
  end

  defp read_container!(descriptor_path) do
    value = evaluate_descriptor!(descriptor_path, "container")
    expected_keys = [:id, :kind, :layer]
    validate_keyword_keys!(value, expected_keys, descriptor_path)

    id = Keyword.fetch!(value, :id)
    kind = Keyword.fetch!(value, :kind)
    layer = Keyword.fetch!(value, :layer)

    unless valid_segment?(id), do: malformed!(descriptor_path, "id must be a stable segment")
    unless kind == :container, do: malformed!(descriptor_path, "kind must be :container")
    unless layer in @layers, do: malformed!(descriptor_path, "layer is invalid")

    %{id: id, kind: kind, layer: layer, path: Path.dirname(descriptor_path)}
  end

  defp validate_container_root!(container_root) do
    descriptor_path = Path.join(container_root, @container_file)

    unless File.regular?(descriptor_path) do
      raise ArgumentError,
            "composition container #{container_root} is missing #{@container_file}"
    end

    read_container!(descriptor_path)
    :ok
  end

  defp discover_container_modules!(container) do
    container.path
    |> File.ls!()
    |> Enum.sort()
    |> Enum.reject(&String.starts_with?(&1, "."))
    |> Enum.map(&Path.join(container.path, &1))
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(fn module_path ->
      descriptor_path = Path.join(module_path, @module_file)

      unless File.regular?(descriptor_path) do
        raise ArgumentError,
              "installed module directory #{module_path} is missing #{@module_file}"
      end

      module_path
      |> read_module!()
      |> Map.merge(%{
        container_id: container.id,
        container_layer: container.layer,
        container_path: container.path
      })
    end)
  end

  defp read_module!(module_path) do
    descriptor_path = Path.join(module_path, @module_file)

    unless File.regular?(descriptor_path) do
      raise ArgumentError, "module #{module_path} is missing #{@module_file}"
    end

    value = evaluate_descriptor!(descriptor_path, "module")
    validate_module_keyword_keys!(value, descriptor_path)

    descriptor = Map.new(value)
    validate_module_fields!(descriptor, descriptor_path)
    Map.put(descriptor, :path, Path.expand(module_path))
  end

  defp evaluate_descriptor!(path, label) do
    case Code.eval_file(path) do
      {value, _binding} -> value
    end
  rescue
    error ->
      reraise ArgumentError,
              [
                message:
                  "malformed Bilimbi #{label} descriptor #{path}: #{Exception.message(error)}"
              ],
              __STACKTRACE__
  end

  defp validate_keyword_keys!(value, expected_keys, path) do
    unless Keyword.keyword?(value) do
      malformed!(path, "descriptor must return a keyword list")
    end

    keys = Keyword.keys(value)

    if length(keys) != length(Enum.uniq(keys)) do
      malformed!(path, "descriptor contains duplicate keys")
    end

    unless Enum.sort(keys) == Enum.sort(expected_keys) do
      malformed!(
        path,
        "expected keys #{inspect(Enum.sort(expected_keys))}, got #{inspect(Enum.sort(keys))}"
      )
    end
  end

  defp validate_module_keyword_keys!(value, path) do
    unless Keyword.keyword?(value) do
      malformed!(path, "descriptor must return a keyword list")
    end

    keys = Keyword.keys(value)

    if length(keys) != length(Enum.uniq(keys)) do
      malformed!(path, "descriptor contains duplicate keys")
    end

    expected_keys =
      if Keyword.get(value, :migrations) do
        [:migration_dispositions | @module_keys]
      else
        @module_keys
      end

    unless Enum.sort(keys) == Enum.sort(expected_keys) do
      malformed!(
        path,
        "expected keys #{inspect(Enum.sort(expected_keys))}, got #{inspect(Enum.sort(keys))}"
      )
    end
  end

  defp validate_module_fields!(descriptor, path) do
    unless valid_module_id?(descriptor.id), do: malformed!(path, "id is invalid")
    unless descriptor.kind == :module, do: malformed!(path, "kind must be :module")
    unless descriptor.layer in @layers, do: malformed!(path, "layer is invalid")
    unless is_boolean(descriptor.required), do: malformed!(path, "required must be boolean")

    unless is_atom(descriptor.otp_app) and not is_nil(descriptor.otp_app) do
      malformed!(path, "otp_app must be a non-nil atom")
    end

    unless is_atom(descriptor.namespace) and not is_nil(descriptor.namespace) do
      malformed!(path, "namespace must be a module atom")
    end

    unless is_list(descriptor.dependencies) and
             Enum.all?(descriptor.dependencies, &valid_module_id?/1) and
             length(descriptor.dependencies) == length(Enum.uniq(descriptor.dependencies)) do
      malformed!(path, "dependencies must be unique stable module IDs")
    end

    unless valid_relative_path?(descriptor.migrations) do
      malformed!(path, "migrations must be nil or a safe relative path")
    end

    if descriptor.migrations &&
         not File.dir?(Path.join(Path.dirname(path), descriptor.migrations)) do
      malformed!(path, "declared migration directory does not exist")
    end

    validate_migration_dispositions!(descriptor, path)

    unless valid_relative_path?(descriptor.web) do
      malformed!(path, "web must be nil or a safe relative path")
    end

    if descriptor.web &&
         not File.regular?(Path.join(Path.dirname(path), descriptor.web)) do
      malformed!(path, "declared web route data file does not exist")
    end

    unless is_nil(descriptor.schema_contract) or is_atom(descriptor.schema_contract) do
      malformed!(path, "schema_contract must be nil or a module atom")
    end

    unless valid_optional_module?(descriptor.contribution_provider) do
      malformed!(path, "contribution_provider must be nil or a non-nil module atom")
    end
  end

  defp validate_migration_dispositions!(%{migrations: nil}, _path), do: :ok

  defp validate_migration_dispositions!(descriptor, descriptor_path) do
    dispositions = Map.fetch!(descriptor, :migration_dispositions)

    unless is_map(dispositions) and map_size(dispositions) > 0 and
             Enum.all?(dispositions, fn {version, disposition} ->
               is_integer(version) and version > 0 and disposition in @migration_dispositions
             end) do
      malformed!(
        descriptor_path,
        "migration_dispositions must map positive versions to :compatible_baseline or :bilimbi_only"
      )
    end

    migration_dir = Path.join(Path.dirname(descriptor_path), descriptor.migrations)
    file_versions = migration_versions!(migration_dir, descriptor_path)
    declared_versions = dispositions |> Map.keys() |> Enum.sort()

    unless file_versions == declared_versions do
      malformed!(
        descriptor_path,
        "migration_dispositions versions #{inspect(declared_versions)} do not match migration files #{inspect(file_versions)}"
      )
    end
  end

  defp migration_versions!(migration_dir, descriptor_path) do
    versions =
      migration_dir
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.map(fn migration_path ->
        case Regex.run(~r/^(\d+)_.*\.exs$/, Path.basename(migration_path),
               capture: :all_but_first
             ) do
          [version] ->
            String.to_integer(version)

          _other ->
            malformed!(
              descriptor_path,
              "invalid migration filename #{Path.basename(migration_path)}"
            )
        end
      end)
      |> Enum.sort()

    if length(versions) != length(Enum.uniq(versions)) do
      malformed!(descriptor_path, "migration directory contains duplicate versions")
    end

    versions
  end

  defp validate_unique!(modules, field, label) do
    duplicates =
      modules
      |> Enum.group_by(&Map.fetch!(&1, field))
      |> Enum.filter(fn {_value, entries} -> length(entries) > 1 end)
      |> Enum.map(fn {value, _entries} -> value end)
      |> Enum.sort()

    if duplicates != [] do
      raise ArgumentError, "duplicate #{label}: #{Enum.map_join(duplicates, ", ", &inspect/1)}"
    end

    modules
  end

  defp validate_unique_migration_versions!(modules) do
    duplicates =
      modules
      |> Enum.flat_map(fn descriptor ->
        descriptor |> Map.get(:migration_dispositions, %{}) |> Map.keys()
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_version, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicates != [] do
      raise ArgumentError, "duplicate migration versions: #{inspect(duplicates)}"
    end

    modules
  end

  defp validate_container_membership!(modules) do
    Enum.each(modules, fn module ->
      if module.layer != module.container_layer do
        raise ArgumentError,
              "module #{module.id} declares layer #{inspect(module.layer)}, " <>
                "but container #{module.container_id} is #{inspect(module.container_layer)}"
      end

      unless String.starts_with?(module.id, module.container_id <> "/") do
        raise ArgumentError,
              "module #{module.id} does not belong to container #{module.container_id}"
      end
    end)

    modules
  end

  defp validate_dependencies!(modules) do
    by_id = Map.new(modules, &{&1.id, &1})

    Enum.each(modules, fn module ->
      Enum.each(module.dependencies, fn dependency_id ->
        dependency =
          Map.get(by_id, dependency_id) ||
            raise ArgumentError,
                  "module #{module.id} declares missing dependency #{dependency_id}"

        unless dependency_allowed?(module, dependency) do
          raise ArgumentError,
                "module #{module.id} in #{module.layer} cannot depend on " <>
                  "#{dependency.id} in #{dependency.layer}"
        end
      end)
    end)

    modules
  end

  defp dependency_allowed?(%{layer: :base}, dependency), do: dependency.layer == :base
  defp dependency_allowed?(%{layer: :core}, dependency), do: dependency.layer in [:base, :core]

  defp dependency_allowed?(%{layer: :domain} = module, dependency) do
    dependency.layer in [:base, :core] or
      (dependency.layer == :domain and dependency.container_id == module.container_id)
  end

  defp dependency_allowed?(%{layer: :extension}, dependency) do
    dependency.layer in [:base, :core, :domain]
  end

  defp topological_sort!(modules) do
    by_id = Map.new(modules, &{&1.id, &1})
    indegrees = Map.new(modules, &{&1.id, length(&1.dependencies)})

    dependents =
      Enum.reduce(modules, %{}, fn module, acc ->
        Enum.reduce(module.dependencies, acc, fn dependency_id, nested_acc ->
          Map.update(nested_acc, dependency_id, [module.id], &[module.id | &1])
        end)
      end)

    queue =
      modules
      |> Enum.filter(&(Map.fetch!(indegrees, &1.id) == 0))
      |> sort_modules()

    {ordered, remaining} = sort_queue(queue, [], indegrees, dependents, by_id)

    if length(ordered) != length(modules) do
      cycle_ids =
        remaining
        |> Enum.filter(fn {_id, degree} -> degree > 0 end)
        |> Enum.map(fn {id, _degree} -> id end)
        |> Enum.sort()

      raise ArgumentError, "module dependency cycle detected: #{Enum.join(cycle_ids, ", ")}"
    end

    ordered
  end

  defp sort_queue([], ordered, indegrees, _dependents, _by_id) do
    {Enum.reverse(ordered), indegrees}
  end

  defp sort_queue([module | queue], ordered, indegrees, dependents, by_id) do
    {indegrees, newly_ready} =
      dependents
      |> Map.get(module.id, [])
      |> Enum.sort()
      |> Enum.reduce({indegrees, []}, fn dependent_id, {degrees, ready} ->
        next_degree = Map.fetch!(degrees, dependent_id) - 1
        degrees = Map.put(degrees, dependent_id, next_degree)

        if next_degree == 0 do
          {degrees, [Map.fetch!(by_id, dependent_id) | ready]}
        else
          {degrees, ready}
        end
      end)

    sort_queue(
      sort_modules(queue ++ newly_ready),
      [module | ordered],
      indegrees,
      dependents,
      by_id
    )
  end

  defp sort_modules(modules) do
    Enum.sort_by(modules, &{layer_rank(&1.layer), &1.id})
  end

  defp layer_rank(layer), do: Enum.find_index(@layers, &(&1 == layer))

  defp valid_segment?(value) when is_binary(value),
    do: Regex.match?(~r/^[a-z][a-z0-9_-]*$/, value)

  defp valid_segment?(_value), do: false

  defp valid_module_id?(value) when is_binary(value) do
    case String.split(value, "/") do
      [container, module] -> valid_segment?(container) and valid_segment?(module)
      _other -> false
    end
  end

  defp valid_module_id?(_value), do: false

  defp valid_relative_path?(nil), do: true

  defp valid_relative_path?(path) when is_binary(path) do
    path != "" and Path.type(path) == :relative and ".." not in Path.split(path)
  end

  defp valid_relative_path?(_path), do: false

  defp valid_optional_module?(nil), do: true
  defp valid_optional_module?(module) when is_atom(module), do: true
  defp valid_optional_module?(_module), do: false

  defp eval_routes!(path) do
    case Code.eval_file(path) do
      {routes, _binding} when is_list(routes) ->
        routes

      {_other, _binding} ->
        raise ArgumentError, "route data file #{path} must return a list of maps"
    end
  end

  defp normalize_route!(route, source) when is_map(route) do
    path = Map.get(route, :path)

    unless is_binary(path) and String.starts_with?(path, "/") do
      raise ArgumentError, "route path must be a binary starting with /"
    end

    if Map.has_key?(route, :live) do
      live = Map.fetch!(route, :live)

      unless is_atom(live) and not is_nil(live) do
        raise ArgumentError, "route live must be a module atom"
      end
    end

    verb = Map.get(route, :verb, :get)

    unless is_atom(verb) and not is_nil(verb) do
      raise ArgumentError, "route verb must be an atom"
    end

    session = Map.get(route, :session, :auth)

    unless session in [:auth, :anonymous, :none] do
      raise ArgumentError, "route session must be :auth, :anonymous, or :none"
    end

    capability = Map.get(route, :capability)

    unless is_nil(capability) or is_binary(capability) do
      raise ArgumentError, "route capability must be a binary or nil"
    end

    if Map.has_key?(route, :controller) do
      controller = Map.fetch!(route, :controller)

      unless is_atom(controller) and not is_nil(controller) do
        raise ArgumentError, "route controller must be a module atom"
      end
    end

    Map.put(route, :source, source)
  end

  defp normalize_route!(_route, _source) do
    raise ArgumentError, "each route must be a map"
  end

  defp malformed!(path, message) do
    raise ArgumentError, "malformed Bilimbi module descriptor #{path}: #{message}"
  end
end

# Load after MixDiscovery is defined. The graph compiler calls this module;
# requiring it at the top of the file made those calls see an undefined module
# whenever config/dev.exs loaded discovery first.
Code.require_file("compile_bilimbi_graph.exs", __DIR__)
