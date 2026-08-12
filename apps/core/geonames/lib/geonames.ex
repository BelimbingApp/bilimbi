defmodule Bilimbi.Core.Geonames do
  @moduledoc """
  Public lookup API for Bilimbi's geographic reference data.

  Callers use ISO and GeoNames identities without depending on Ecto schemas or
  table details. Fresh installations may return empty results until reference
  data has been imported.
  """

  import Ecto.Query

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Geonames.Admin1
  alias Bilimbi.Core.Geonames.Admin1Summary
  alias Bilimbi.Core.Geonames.City
  alias Bilimbi.Core.Geonames.CitySummary
  alias Bilimbi.Core.Geonames.Country
  alias Bilimbi.Core.Geonames.CountrySummary
  alias Bilimbi.Core.Geonames.Postcode
  alias Bilimbi.Core.Geonames.PostcodeSummary
  alias Bilimbi.Core.Geonames.ReferenceData

  @type import_error ::
          {:invalid_dataset, term()}
          | {:invalid_country_iso, term()}
          | {:download, atom() | {:postcodes, String.t()}, term()}
          | {:extract, atom() | {:postcodes, String.t()}, term()}
          | {:import, atom() | {:postcodes, String.t()}, term()}

  @doc """
  Downloads and imports the selected canonical GeoNames datasets.

  Supported options: `:datasets`, `:postcodes`, `:cache_dir`, `:force`,
  `:ttl_days`, and `:receive_timeout`. Every dataset import is atomic and a
  payload that yields no valid rows is rejected with
  `{:error, {:import, dataset, :no_valid_rows}}`; a failed import restores
  the previously known-good download cache.
  """
  @spec import_reference_data(keyword()) :: {:ok, map()} | {:error, import_error()}
  def import_reference_data(opts \\ []) do
    ReferenceData.run(
      Keyword.take(opts, [:datasets, :postcodes, :cache_dir, :force, :ttl_days, :receive_timeout])
    )
  end

  @spec list_countries() :: [CountrySummary.t()]
  def list_countries do
    from(country in Country, order_by: [asc: country.country, asc: country.iso])
    |> Repo.all()
    |> Enum.map(&CountrySummary.from_schema/1)
  end

  @spec get_country(String.t()) :: CountrySummary.t() | nil
  def get_country(iso) do
    with {:ok, iso} <- normalize_iso(iso),
         %Country{} = country <- Repo.get_by(Country, iso: iso) do
      CountrySummary.from_schema(country)
    else
      _other -> nil
    end
  end

  @spec list_admin1(String.t()) :: [Admin1Summary.t()]
  def list_admin1(country_iso) do
    case normalize_iso(country_iso) do
      {:ok, iso} ->
        from(admin1 in Admin1,
          where: fragment("split_part(?, '.', 1) = ?", admin1.code, ^iso),
          order_by: [asc: admin1.name, asc: admin1.code]
        )
        |> Repo.all()
        |> Enum.map(&Admin1Summary.from_schema/1)

      :error ->
        []
    end
  end

  @spec lookup_postcode(String.t(), String.t()) :: [PostcodeSummary.t()]
  def lookup_postcode(country_iso, postcode) do
    with {:ok, iso} <- normalize_iso(country_iso),
         {:ok, postcode} <- normalize_required(postcode) do
      from(entry in Postcode,
        where: entry.country_iso == ^iso and entry.postcode == ^postcode,
        order_by: [asc: entry.place_name, asc: entry.id]
      )
      |> Repo.all()
      |> Enum.map(&PostcodeSummary.from_schema/1)
    else
      :error -> []
    end
  end

  @spec get_city_by_geoname_id(pos_integer()) :: CitySummary.t() | nil
  def get_city_by_geoname_id(geoname_id)
      when is_integer(geoname_id) and geoname_id > 0 do
    case Repo.get_by(City, geoname_id: geoname_id) do
      nil -> nil
      city -> CitySummary.from_schema(city)
    end
  end

  def get_city_by_geoname_id(_geoname_id), do: nil

  defp normalize_iso(value) do
    case normalize_required(value) do
      {:ok, iso} when byte_size(iso) == 2 -> {:ok, String.upcase(iso)}
      _other -> :error
    end
  end

  defp normalize_required(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_required(_value), do: :error
end
