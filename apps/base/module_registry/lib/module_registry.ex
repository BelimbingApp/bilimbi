defmodule Bilimbi.Base.ModuleRegistry do
  @moduledoc """
  Provides Mix-approved installed module metadata to runtime coordinators.

  Mix-time source discovery validates and orders the complete module graph,
  then records each descriptor and its resolved position in OTP application
  metadata. Runtime discovery validates that metadata and consumes the approved
  order without repeating the graph algorithm or depending on checkout paths.
  """

  @layers [:base, :core, :domain, :extension]

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
    |> validate_unique!(:order, "resolved module order")
    |> Enum.sort_by(& &1.order)
    |> validate_resolved_order!()
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

  defp layer_rank(layer), do: Enum.find_index(@layers, &(&1 == layer))
end
