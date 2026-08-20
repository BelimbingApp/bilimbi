defmodule Bilimbi.Core.Geonames.Importer do
  @moduledoc """
  Internal GeoNames file import.

  Policy: each dataset import is atomic. All batches run inside one
  transaction; a database failure in any batch rolls the whole dataset back
  and is reported as `{:error, {:database, message}}` instead of escaping as
  an exception. A file that yields zero valid rows is rejected with
  `{:error, :no_valid_rows}` so a truncated or malformed payload can never
  masquerade as a successful empty import.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Geonames.Admin1
  alias Bilimbi.Core.Geonames.City
  alias Bilimbi.Core.Geonames.Country
  alias Bilimbi.Core.Geonames.Postcode
  alias Bilimbi.Core.Geonames.PostcodeOverrides

  @chunk_size 500

  @type result :: %{imported: non_neg_integer(), skipped: non_neg_integer()}

  @spec countries(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def countries(path, opts \\ []) do
    atomic_import(path, &parse_country/1, &upsert_countries(&1, opts), opts)
  end

  @spec admin1(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def admin1(path, opts \\ []) do
    atomic_import(path, &parse_admin1/1, &upsert_admin1(&1, opts), opts)
  end

  @spec cities(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def cities(path, opts \\ []) do
    atomic_import(path, &parse_city/1, &upsert_cities(&1, opts), opts)
  end

  @spec postcodes(String.t(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def postcodes(country_iso, path, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    iso = normalize_iso(country_iso)

    cond do
      is_nil(iso) ->
        {:error, {:invalid_country_iso, country_iso}}

      is_nil(repo.get_by(Country, iso: iso)) ->
        {:error, {:country_not_found, iso}}

      true ->
        repo.transaction(
          fn ->
            repo.delete_all(from(entry in Postcode, where: entry.country_iso == ^iso))

            case stream_import(path, &parse_postcode(&1, iso), &insert_postcodes(&1, opts)) do
              {:ok, %{imported: 0}} ->
                repo.rollback(:no_valid_rows)

              {:ok, result} ->
                :ok = PostcodeOverrides.reapply_country(iso, repo)
                result

              {:error, reason} ->
                repo.rollback(reason)
            end
          end,
          timeout: :infinity
        )
    end
  end

  defp atomic_import(path, parser, persist, opts) do
    if File.regular?(path) do
      repo(opts).transaction(
        fn ->
          case stream_import(path, parser, persist) do
            {:ok, %{imported: 0}} -> repo(opts).rollback(:no_valid_rows)
            {:ok, result} -> result
            {:error, reason} -> repo(opts).rollback(reason)
          end
        end,
        timeout: :infinity
      )
    else
      {:error, {:file_not_found, path}}
    end
  end

  defp stream_import(path, parser, persist) do
    path
    |> File.stream!(:line, [])
    |> Stream.map(parser)
    |> Stream.chunk_every(@chunk_size)
    |> Enum.reduce_while({:ok, %{imported: 0, skipped: 0}}, fn parsed, {:ok, totals} ->
      rows = for {:ok, row} <- parsed, do: row
      skipped = Enum.count(parsed, &match?(:skip, &1))

      case persist_rows(persist, rows) do
        :ok ->
          {:cont,
           {:ok,
            %{
              imported: totals.imported + length(rows),
              skipped: totals.skipped + skipped
            }}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_rows(_persist, []), do: :ok

  defp persist_rows(persist, rows) do
    persist.(rows)
    :ok
  rescue
    error -> {:error, {:database, Exception.message(error)}}
  end

  defp upsert_countries(rows, opts) do
    timestamped = add_timestamps(rows)

    repo(opts).insert_all(Country, timestamped,
      conflict_target: [:iso],
      on_conflict:
        {:replace,
         [
           :iso3,
           :iso_numeric,
           :capital,
           :area,
           :population,
           :continent,
           :tld,
           :currency_code,
           :currency_name,
           :phone,
           :postal_code_format,
           :postal_code_regex,
           :languages,
           :geoname_id,
           :updated_at
         ]}
    )
  end

  defp upsert_admin1(rows, opts) do
    repo(opts).insert_all(Admin1, add_timestamps(rows),
      conflict_target: [:code],
      on_conflict: {:replace, [:alt_name, :geoname_id, :updated_at]}
    )
  end

  defp upsert_cities(rows, opts) do
    repo(opts).insert_all(City, add_timestamps(rows),
      conflict_target: [:geoname_id],
      on_conflict:
        {:replace,
         [
           :name,
           :ascii_name,
           :alternate_names,
           :latitude,
           :longitude,
           :country_iso,
           :admin1_code,
           :population,
           :timezone,
           :modification_date,
           :updated_at
         ]}
    )
  end

  defp insert_postcodes(rows, opts) do
    repo(opts).insert_all(Postcode, add_timestamps(rows))
  end

  defp add_timestamps(rows) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    Enum.map(rows, &Map.merge(&1, %{created_at: now, updated_at: now}))
  end

  defp parse_country(line) do
    with {:ok, parts} <- parts(line, 17),
         {:ok, iso} <- required(parts, 0),
         {:ok, iso3} <- required(parts, 1),
         {:ok, iso_numeric} <- required(parts, 2),
         {:ok, country} <- required(parts, 4),
         {:ok, continent} <- required(parts, 8) do
      {:ok,
       %{
         iso: String.upcase(iso),
         iso3: String.upcase(iso3),
         iso_numeric: iso_numeric,
         country: country,
         capital: optional(parts, 5),
         area: float(parts, 6),
         population: integer(parts, 7) || 0,
         continent: String.upcase(continent),
         tld: optional(parts, 9),
         currency_code: optional(parts, 10),
         currency_name: optional(parts, 11),
         phone: optional(parts, 12),
         postal_code_format: optional(parts, 13),
         postal_code_regex: optional(parts, 14),
         languages: optional(parts, 15),
         geoname_id: integer(parts, 16)
       }}
    else
      _other -> :skip
    end
  end

  defp parse_admin1(line) do
    with {:ok, parts} <- parts(line, 4),
         {:ok, code} <- required(parts, 0),
         {:ok, name} <- required(parts, 1) do
      {:ok,
       %{
         code: code,
         name: name,
         alt_name: optional(parts, 2),
         geoname_id: integer(parts, 3)
       }}
    else
      _other -> :skip
    end
  end

  defp parse_city(line) do
    with {:ok, parts} <- parts(line, 19),
         geoname_id when is_integer(geoname_id) <- integer(parts, 0),
         {:ok, name} <- required(parts, 1),
         {:ok, ascii_name} <- required(parts, 2),
         %Decimal{} = latitude <- decimal(parts, 4),
         %Decimal{} = longitude <- decimal(parts, 5),
         {:ok, country_iso} <- required(parts, 8),
         {:ok, timezone} <- required(parts, 17) do
      {:ok,
       %{
         geoname_id: geoname_id,
         name: name,
         ascii_name: ascii_name,
         alternate_names: optional(parts, 3),
         latitude: latitude,
         longitude: longitude,
         country_iso: String.upcase(country_iso),
         admin1_code: optional(parts, 10),
         population: integer(parts, 14) || 0,
         timezone: timezone,
         modification_date: date(parts, 18)
       }}
    else
      _other -> :skip
    end
  end

  defp parse_postcode(line, expected_iso) do
    with {:ok, parts} <- parts(line, 3),
         {:ok, country_iso} <- required(parts, 0),
         true <- String.upcase(country_iso) == expected_iso,
         {:ok, postcode} <- required(parts, 1),
         {:ok, place_name} <- required(parts, 2) do
      {:ok,
       %{
         country_iso: expected_iso,
         postcode: postcode,
         place_name: place_name,
         admin1_code: optional(parts, 4),
         admin_name1: optional(parts, 3),
         admin_code1: optional(parts, 4),
         admin_name2: optional(parts, 5),
         admin_code2: optional(parts, 6),
         admin_name3: optional(parts, 7),
         admin_code3: optional(parts, 8),
         latitude: decimal(parts, 9),
         longitude: decimal(parts, 10),
         accuracy: integer(parts, 11)
       }}
    else
      _other -> :skip
    end
  end

  defp parts(line, minimum) do
    line = line |> String.trim_trailing("\n") |> String.trim_trailing("\r")

    if line == "" or String.starts_with?(line, "#") do
      :skip
    else
      fields = String.split(line, "\t", trim: false)
      if length(fields) >= minimum, do: {:ok, fields}, else: :skip
    end
  end

  defp required(parts, index) do
    case optional(parts, index) do
      nil -> :error
      value -> {:ok, value}
    end
  end

  defp optional(parts, index) do
    case Enum.at(parts, index) do
      nil -> nil
      value -> if String.trim(value) == "", do: nil, else: String.trim(value)
    end
  end

  defp integer(parts, index) do
    case optional(parts, index) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {number, ""} -> number
          _other -> nil
        end
    end
  end

  defp float(parts, index) do
    case optional(parts, index) do
      nil ->
        nil

      value ->
        case Float.parse(value) do
          {number, ""} -> number
          _other -> nil
        end
    end
  end

  defp decimal(parts, index) do
    case optional(parts, index) do
      nil ->
        nil

      value ->
        case Decimal.parse(value) do
          {number, ""} -> number
          _other -> nil
        end
    end
  end

  defp date(parts, index) do
    case optional(parts, index) do
      nil ->
        nil

      value ->
        case Date.from_iso8601(value) do
          {:ok, date} -> date
          {:error, _reason} -> nil
        end
    end
  end

  defp normalize_iso(value) when is_binary(value) do
    iso = value |> String.trim() |> String.upcase()
    if Regex.match?(~r/^[A-Z]{2}$/, iso), do: iso
  end

  defp normalize_iso(_value), do: nil
  defp repo(opts), do: Keyword.get(opts, :repo, Repo)
end
