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
    :schema_contract
  ]

  Code.require_file("compile_bilimbi_graph.exs", __DIR__)

  @type descriptor :: %{
          id: String.t(),
          kind: :module,
          layer: :base | :core | :domain | :extension,
          required: boolean(),
          otp_app: atom(),
          namespace: module(),
          dependencies: [String.t()],
          migrations: nil | String.t(),
          schema_contract: nil | module(),
          path: String.t(),
          container_id: String.t()
        }

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

    descriptor_source =
      [
        Path.join(workspace_root, "apps/*/#{@container_file}"),
        Path.join(workspace_root, "apps/*/*/#{@module_file}")
      ]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.sort()
      |> Enum.map_join("\0", fn descriptor_path ->
        relative_path = Path.relative_to(descriptor_path, workspace_root)
        relative_path <> "\0" <> File.read!(descriptor_path)
      end)

    :sha256
    |> :crypto.hash(descriptor_source)
    |> Base.encode16(case: :lower)
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
    validate_keyword_keys!(value, @module_keys, descriptor_path)

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

    unless is_nil(descriptor.schema_contract) or is_atom(descriptor.schema_contract) do
      malformed!(path, "schema_contract must be nil or a module atom")
    end
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

  defp malformed!(path, message) do
    raise ArgumentError, "malformed Bilimbi module descriptor #{path}: #{message}"
  end
end
