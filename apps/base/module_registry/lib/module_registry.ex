defmodule Bilimbi.Base.ModuleRegistry do
  @moduledoc """
  Provides Mix-approved installed module metadata to runtime coordinators.

  Mix-time source discovery validates and orders the complete module graph,
  then records each descriptor and its resolved position in OTP application
  metadata. Runtime discovery validates that metadata and consumes the approved
  order without repeating the graph algorithm or depending on checkout paths.
  """

  @layers [:base, :core, :domain, :extension]
  @migration_dispositions [:compatible_baseline, :bilimbi_only]

  @spec installed_modules!() :: [map()]
  def installed_modules! do
    modules =
      Application.loaded_applications()
      |> Enum.flat_map(fn {app, _description, _version} ->
        case Application.get_env(app, :bilimbi_module) do
          nil -> []
          descriptor -> [Map.put(descriptor, :path, Application.app_dir(app))]
        end
      end)

    modules
    |> validate_unique!(:id, "stable module ID")
    |> validate_unique!(:otp_app, "OTP application ID")
    |> validate_unique_graph_fingerprint!()
    |> validate_unique!(:order, "resolved module order")
    |> Enum.sort_by(& &1.order)
    |> validate_resolved_order!()
    |> validate_migrations!()
  end

  defp validate_unique_graph_fingerprint!(modules) do
    fingerprints = modules |> Enum.map(& &1.graph_fingerprint) |> Enum.uniq()

    if length(fingerprints) > 1 do
      raise ArgumentError,
            "installed module metadata was compiled from different workspace graphs; recompile the workspace"
    end

    modules
  end

  @spec migration_modules!() :: [map()]
  def migration_modules! do
    Enum.filter(installed_modules!(), &is_binary(&1.migrations))
  end

  @spec migration_paths!() :: [String.t()]
  def migration_paths! do
    Enum.map(migration_modules!(), fn descriptor ->
      Application.app_dir(descriptor.otp_app, descriptor.migrations)
    end)
  end

  @doc """
  Absolute paths to the module-owned dev-seed scripts, in dependency order.

  A module ships sample data for local development by declaring
  `dev_seed: "priv/dev_seed.exs"` in its descriptor; modules that ship none
  declare `dev_seed: nil`. Ordering follows each descriptor's resolved `:order`,
  so a dependency's sample data is seeded before a dependent's — a dependent's
  script may reference the earlier data through a right-direction public API.

  Unlike `migration_paths!/0`, this reads the loaded descriptors directly rather
  than through `installed_modules!/0`: dev seeding is a best-effort convenience
  that seeds whatever modules are loaded, so it must not require the whole graph
  to be present the way a migration run does.
  """
  @spec dev_seed_paths!() :: [String.t()]
  def dev_seed_paths! do
    Application.loaded_applications()
    |> Enum.map(fn {app, _description, _version} -> Application.get_env(app, :bilimbi_module) end)
    |> Enum.filter(&(is_map(&1) and is_binary(Map.get(&1, :dev_seed))))
    |> Enum.sort_by(& &1.order)
    |> Enum.map(fn descriptor ->
      Application.app_dir(descriptor.otp_app, descriptor.dev_seed)
    end)
  end

  @spec migration_dispositions!() :: %{pos_integer() => :compatible_baseline | :bilimbi_only}
  def migration_dispositions! do
    migration_modules!()
    |> Enum.reduce(%{}, fn descriptor, dispositions ->
      Enum.reduce(descriptor.migration_dispositions, dispositions, fn {version, disposition},
                                                                      acc ->
        case Map.fetch(acc, version) do
          :error ->
            Map.put(acc, version, disposition)

          {:ok, _existing} ->
            raise ArgumentError, "duplicate migration version: #{version}"
        end
      end)
    end)
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

  defp validate_resolved_order!(modules) do
    expected_orders = if modules == [], do: [], else: Enum.to_list(0..(length(modules) - 1))

    unless Enum.map(modules, & &1.order) == expected_orders do
      raise ArgumentError, "installed module order is not contiguous from zero"
    end

    by_id = Map.new(modules, &{&1.id, &1})

    Enum.each(modules, fn module ->
      unless module.layer in @layers do
        raise ArgumentError, "module #{module.id} has invalid layer #{inspect(module.layer)}"
      end

      Enum.each(module.dependencies, fn dependency_id ->
        dependency =
          Map.get(by_id, dependency_id) ||
            raise ArgumentError,
                  "module #{module.id} declares missing dependency #{dependency_id}"

        unless dependency.order < module.order do
          raise ArgumentError,
                "module #{module.id} is ordered before dependency #{dependency_id}"
        end
      end)
    end)

    modules
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [left, right] ->
      if layer_rank(left.layer) > layer_rank(right.layer) do
        raise ArgumentError,
              "installed module order moves backward from #{left.layer} to #{right.layer}"
      end
    end)

    modules
  end

  defp validate_migrations!(modules) do
    Enum.each(modules, &validate_module_migrations!/1)

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

  defp validate_module_migrations!(%{migrations: nil} = descriptor) do
    if Map.has_key?(descriptor, :migration_dispositions) do
      raise ArgumentError,
            "module #{descriptor.id} must omit migration_dispositions when migrations is nil"
    end
  end

  defp validate_module_migrations!(%{migrations: migrations} = descriptor)
       when is_binary(migrations) do
    unless valid_relative_path?(migrations) do
      raise ArgumentError, "module #{descriptor.id} has an unsafe migration path"
    end

    dispositions = Map.get(descriptor, :migration_dispositions)

    unless is_map(dispositions) and map_size(dispositions) > 0 and
             Enum.all?(dispositions, fn {version, disposition} ->
               is_integer(version) and version > 0 and disposition in @migration_dispositions
             end) do
      raise ArgumentError,
            "module #{descriptor.id} has invalid migration_dispositions metadata"
    end

    migration_dir = Application.app_dir(descriptor.otp_app, migrations)

    unless File.dir?(migration_dir) do
      raise ArgumentError, "module #{descriptor.id} migration directory is missing"
    end

    file_versions = migration_versions!(descriptor.id, migration_dir)
    declared_versions = dispositions |> Map.keys() |> Enum.sort()

    unless file_versions == declared_versions do
      raise ArgumentError,
            "module #{descriptor.id} migration_dispositions versions #{inspect(declared_versions)} " <>
              "do not match migration files #{inspect(file_versions)}"
    end
  end

  defp validate_module_migrations!(descriptor) do
    raise ArgumentError, "module #{descriptor.id} has invalid migrations metadata"
  end

  defp migration_versions!(module_id, migration_dir) do
    versions =
      migration_dir
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.map(fn migration_path ->
        case Regex.run(~r/^(\d+)_.*\.exs$/, Path.basename(migration_path),
               capture: :all_but_first
             ) do
          [version] -> String.to_integer(version)
          _other -> raise ArgumentError, "module #{module_id} has an invalid migration filename"
        end
      end)
      |> Enum.sort()

    if length(versions) != length(Enum.uniq(versions)) do
      raise ArgumentError, "module #{module_id} has duplicate migration versions"
    end

    versions
  end

  defp valid_relative_path?(path) do
    path != "" and Path.type(path) == :relative and ".." not in Path.split(path)
  end

  defp layer_rank(layer), do: Enum.find_index(@layers, &(&1 == layer))
end
