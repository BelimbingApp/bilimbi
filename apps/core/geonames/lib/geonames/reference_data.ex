defmodule Bilimbi.Core.Geonames.ReferenceData do
  @moduledoc false

  alias Bilimbi.Core.Geonames.Downloader
  alias Bilimbi.Core.Geonames.Importer

  @base_dump_url "https://download.geonames.org/export/dump"
  @postcode_url "https://download.geonames.org/export/zip"
  @dataset_order [:countries, :admin1, :cities]

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    with {:ok, datasets} <- normalize_datasets(Keyword.get(opts, :datasets, @dataset_order)),
         {:ok, postcodes} <- normalize_postcodes(Keyword.get(opts, :postcodes, [])),
         {:ok, results} <- import_datasets(datasets, opts),
         {:ok, postcode_results} <- import_postcodes(postcodes, opts) do
      {:ok, Map.put(results, :postcodes, postcode_results)}
    end
  end

  defp import_datasets(datasets, opts) do
    Enum.reduce_while(@dataset_order, {:ok, %{}}, fn dataset, {:ok, results} ->
      if dataset in datasets do
        case download_and_import(dataset, opts) do
          {:ok, result} -> {:cont, {:ok, Map.put(results, dataset, result)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      else
        {:cont, {:ok, results}}
      end
    end)
  end

  defp import_postcodes(country_codes, opts) do
    Enum.reduce_while(country_codes, {:ok, %{}}, fn iso, {:ok, results} ->
      case download_and_import({:postcodes, iso}, opts) do
        {:ok, result} -> {:cont, {:ok, Map.put(results, iso, result)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp download_and_import(dataset, opts) do
    %{url: url, filename: filename, entry: entry} = source(dataset)
    cache_dir = cache_dir(opts)
    destination = Path.join(cache_dir, filename)
    downloader = Keyword.get(opts, :downloader, &Downloader.download/3)

    download_opts =
      Keyword.take(opts, [:connect_timeout, :force, :receive_timeout, :req_options, :ttl_days])

    with_cache_protection(destination, entry && Path.join(cache_dir, entry), fn ->
      with {:ok, download} <- downloader.(url, destination, download_opts),
           {:ok, import_path} <- import_path(dataset, download, entry, cache_dir),
           {:ok, result} <- import_file(dataset, import_path, opts) do
        {:ok,
         result
         |> Map.put(:cached, download.cached)
         # `:status` is what separates "the server confirmed you are current"
         # from "the download failed and we kept what we had". Dropping it here
         # made those two identical to every caller (#273).
         |> Map.put(:download_status, download.status)
         |> Map.put(:cached_at, Map.get(download, :cached_at))}
      else
        {:error, {:download, _dataset, _reason} = reason} -> {:error, reason}
        {:error, {:extract, _dataset, _reason} = reason} -> {:error, reason}
        {:error, {:import, _dataset, _reason} = reason} -> {:error, reason}
        {:error, reason} -> {:error, {:download, dataset, reason}}
      end
    end)
  end

  # A fresh download replaces the cached payload before the import can
  # validate it. Snapshot the previous payload (and its etag) first; when the
  # import reports an operational failure, restore the known-good cache and
  # drop any extracted entry so the next run re-extracts from the restored
  # archive instead of trusting a stale extraction.
  defp with_cache_protection(destination, extracted_path, fun) do
    etag_path = destination <> ".etag"
    backup_path = destination <> ".good-#{System.unique_integer([:positive])}"
    etag_backup_path = backup_path <> ".etag"

    with :ok <- backup_file(destination, backup_path),
         :ok <- backup_file(etag_path, etag_backup_path) do
      case fun.() do
        {:ok, result} ->
          File.rm(backup_path)
          File.rm(etag_backup_path)
          {:ok, result}

        {:error, reason} ->
          restore_file(backup_path, destination)
          restore_file(etag_backup_path, etag_path)
          if extracted_path, do: File.rm(extracted_path)
          {:error, reason}
      end
    end
  end

  defp backup_file(path, backup_path) do
    if File.regular?(path) do
      File.cp(path, backup_path)
    else
      File.rm(backup_path) |> normalize_rm()
    end
  end

  defp restore_file(backup_path, path) do
    if File.regular?(backup_path) do
      File.rename(backup_path, path)
    else
      File.rm(path) |> normalize_rm()
    end
  end

  defp normalize_rm(:ok), do: :ok
  defp normalize_rm({:error, :enoent}), do: :ok
  defp normalize_rm(error), do: error

  defp import_path(_dataset, download, nil, _cache_dir), do: {:ok, download.path}

  defp import_path(dataset, download, entry, cache_dir) do
    extracted_path = Path.join(cache_dir, entry)

    if download.cached and File.regular?(extracted_path) do
      {:ok, extracted_path}
    else
      File.rm(extracted_path)

      case :zip.extract(String.to_charlist(download.path),
             cwd: String.to_charlist(cache_dir),
             file_list: [String.to_charlist(entry)]
           ) do
        {:ok, _files} -> {:ok, extracted_path}
        {:error, reason} -> {:error, {:extract, dataset, reason}}
      end
    end
  end

  defp import_file(:countries, path, opts),
    do: wrap_import(:countries, Importer.countries(path, opts))

  defp import_file(:admin1, path, opts), do: wrap_import(:admin1, Importer.admin1(path, opts))
  defp import_file(:cities, path, opts), do: wrap_import(:cities, Importer.cities(path, opts))

  defp import_file({:postcodes, iso} = dataset, path, opts) do
    wrap_import(dataset, Importer.postcodes(iso, path, opts))
  end

  defp wrap_import(_dataset, {:ok, result}), do: {:ok, result}
  defp wrap_import(dataset, {:error, reason}), do: {:error, {:import, dataset, reason}}

  defp source(:countries) do
    %{url: "#{@base_dump_url}/countryInfo.txt", filename: "countryInfo.txt", entry: nil}
  end

  defp source(:admin1) do
    %{
      url: "#{@base_dump_url}/admin1CodesASCII.txt",
      filename: "admin1CodesASCII.txt",
      entry: nil
    }
  end

  defp source(:cities) do
    %{
      url: "#{@base_dump_url}/cities15000.zip",
      filename: "cities15000.zip",
      entry: "cities15000.txt"
    }
  end

  defp source({:postcodes, iso}) do
    %{url: "#{@postcode_url}/#{iso}.zip", filename: "#{iso}.zip", entry: "#{iso}.txt"}
  end

  defp normalize_datasets(datasets) when is_list(datasets) do
    invalid = Enum.reject(datasets, &(&1 in @dataset_order))

    case invalid do
      [] -> {:ok, Enum.uniq(datasets)}
      [dataset | _rest] -> {:error, {:invalid_dataset, dataset}}
    end
  end

  defp normalize_datasets(dataset), do: {:error, {:invalid_dataset, dataset}}

  defp normalize_postcodes(country_codes) when is_list(country_codes) do
    country_codes
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, codes} ->
      case normalize_iso(value) do
        nil -> {:halt, {:error, {:invalid_country_iso, value}}}
        iso -> {:cont, {:ok, [iso | codes]}}
      end
    end)
    |> case do
      {:ok, codes} -> {:ok, codes |> Enum.uniq() |> Enum.sort()}
      error -> error
    end
  end

  defp normalize_postcodes(value), do: {:error, {:invalid_country_iso, value}}

  defp normalize_iso(value) when is_binary(value) do
    iso = value |> String.trim() |> String.upcase()
    if Regex.match?(~r/^[A-Z]{2}$/, iso), do: iso
  end

  defp normalize_iso(_value), do: nil

  defp cache_dir(opts) do
    Keyword.get_lazy(opts, :cache_dir, fn ->
      System.get_env("GEONAMES_CACHE_DIR") ||
        Application.get_env(
          :bilimbi_core_geonames,
          :cache_dir,
          Path.join(System.tmp_dir!(), "bilimbi/geonames")
        )
    end)
  end
end
