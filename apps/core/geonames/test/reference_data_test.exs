defmodule Bilimbi.Core.Geonames.ReferenceDataTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Core.Geonames
  alias Bilimbi.Core.Geonames.ReferenceData

  import Bilimbi.Core.Geonames.TestFixtures

  setup do
    create_geonames_tables!()

    directory =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-geonames-reference-data-#{System.unique_integer([:positive])}"
      )

    source_dir = Path.join(directory, "source")
    cache_dir = Path.join(directory, "cache")
    File.mkdir_p!(source_dir)
    File.mkdir_p!(cache_dir)
    on_exit(fn -> File.rm_rf!(directory) end)

    File.write!(Path.join(source_dir, "countryInfo.txt"), country_file())
    File.write!(Path.join(source_dir, "admin1CodesASCII.txt"), admin1_file())
    create_zip!(Path.join(source_dir, "cities15000.zip"), "cities15000.txt", city_file())
    create_zip!(Path.join(source_dir, "MY.zip"), "MY.txt", postcode_file())

    downloader = fn _url, destination, _opts ->
      File.cp!(Path.join(source_dir, Path.basename(destination)), destination)
      {:ok, %{path: destination, cached: false, status: 200, etag: nil}}
    end

    %{cache_dir: cache_dir, downloader: downloader, source_dir: source_dir}
  end

  test "coordinates ordered downloads, safe extraction, and imports", context do
    assert {:ok, results} =
             ReferenceData.run(
               cache_dir: context.cache_dir,
               downloader: context.downloader,
               postcodes: ["my"]
             )

    assert results.countries.imported == 1
    assert results.admin1.imported == 1
    assert results.cities.imported == 1
    assert results.postcodes["MY"].imported == 1
    assert Geonames.get_city_by_geoname_id(1_735_161).name == "Kuala Lumpur"
    assert [%{place_name: "Kuala Lumpur"}] = Geonames.lookup_postcode("MY", "50000")
  end

  test "the public facade whitelists supported options", context do
    assert {:error, {:invalid_dataset, {:invalid, "unknown"}}} =
             Geonames.import_reference_data(
               datasets: [{:invalid, "unknown"}],
               cache_dir: context.cache_dir
             )
  end

  test "a failed import restores the known-good download cache", context do
    assert {:ok, _results} =
             ReferenceData.run(
               datasets: [:countries],
               cache_dir: context.cache_dir,
               downloader: context.downloader
             )

    assert Geonames.get_country("MY").country == "Malaysia"

    cached_path = Path.join(context.cache_dir, "countryInfo.txt")
    known_good = File.read!(cached_path)

    File.write!(
      Path.join(context.source_dir, "countryInfo.txt"),
      "<html>200 OK error page</html>\n"
    )

    assert {:error, {:import, :countries, :no_valid_rows}} =
             ReferenceData.run(
               datasets: [:countries],
               cache_dir: context.cache_dir,
               downloader: context.downloader
             )

    assert File.read!(cached_path) == known_good
    assert Geonames.get_country("MY").country == "Malaysia"
  end

  defp create_zip!(path, entry, contents) do
    assert {:ok, _filename} =
             :zip.create(String.to_charlist(path), [
               {String.to_charlist(entry), contents}
             ])
  end

  defp country_file do
    "MY\tMYS\t458\tMY\tMalaysia\tKuala Lumpur\t329847\t34100000\tAS\t.my\tMYR\tRinggit\t60\t#####\t^[0-9]{5}$\tms,en\t1733045\tSG,TH\t\n"
  end

  defp admin1_file, do: "MY.14\tKuala Lumpur\tKuala Lumpur\t1733046\n"

  defp city_file do
    "1735161\tKuala Lumpur\tKuala Lumpur\tKL\t3.1412\t101.6865\tP\tPPLC\tMY\t\t14\t\t\t\t1453975\t\t22\tAsia/Kuala_Lumpur\t2026-01-02\n"
  end

  defp postcode_file do
    "MY\t50000\tKuala Lumpur\tKuala Lumpur\t14\t\t\t\t\t3.139\t101.6869\t4\n"
  end
end
