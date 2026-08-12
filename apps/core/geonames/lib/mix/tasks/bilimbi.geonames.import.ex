defmodule Mix.Tasks.Bilimbi.Geonames.Import do
  use Mix.Task

  @shortdoc "Downloads and imports canonical GeoNames reference data"

  @moduledoc """
  Downloads and imports GeoNames reference datasets.

      mix bilimbi.geonames.import
      mix bilimbi.geonames.import --datasets countries,admin1,cities
      mix bilimbi.geonames.import --datasets countries,admin1 --postcodes MY,SG
      mix bilimbi.geonames.import --cache-dir /var/lib/bilimbi/geonames --force

  Countries, first-level administrative divisions, and cities are imported by
  default. Postcodes are intentionally opt-in because their size varies widely
  by country.
  """

  alias Bilimbi.Core.Geonames

  @switches [datasets: :string, postcodes: :string, cache_dir: :string, force: :boolean]

  @impl Mix.Task
  def run(args) do
    {parsed, remaining} = OptionParser.parse!(args, strict: @switches)

    if remaining != [] do
      Mix.raise("unexpected arguments: #{Enum.join(remaining, " ")}")
    end

    Mix.Task.run("app.start")

    opts =
      []
      |> maybe_put(:datasets, parse_datasets(parsed[:datasets]))
      |> maybe_put(:postcodes, parse_csv(parsed[:postcodes]))
      |> maybe_put(:cache_dir, parsed[:cache_dir])
      |> maybe_put(:force, parsed[:force])

    case Geonames.import_reference_data(opts) do
      {:ok, results} -> print_results(results)
      {:error, reason} -> Mix.raise("GeoNames import failed: #{inspect(reason)}")
    end
  end

  defp parse_datasets(nil), do: nil

  defp parse_datasets(value) do
    value
    |> parse_csv()
    |> Enum.map(fn
      "countries" -> :countries
      "admin1" -> :admin1
      "cities" -> :cities
      unknown -> {:invalid, unknown}
    end)
  end

  defp parse_csv(nil), do: nil

  defp parse_csv(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp print_results(results) do
    for dataset <- [:countries, :admin1, :cities], result = results[dataset] do
      Mix.shell().info(result_line(to_string(dataset), result))
    end

    results
    |> Map.fetch!(:postcodes)
    |> Enum.sort()
    |> Enum.each(fn {iso, result} ->
      Mix.shell().info(result_line("postcodes #{iso}", result))
    end)
  end

  defp result_line(dataset, result) do
    source = if result.cached, do: "cached download", else: "fresh download"
    "#{dataset}: imported #{result.imported}, skipped #{result.skipped} (#{source})"
  end
end
