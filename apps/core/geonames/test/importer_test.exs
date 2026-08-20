defmodule Bilimbi.Core.Geonames.ImporterTest do
  use Bilimbi.Base.Database.DataCase, async: true

  alias Bilimbi.Base.Repo
  alias Bilimbi.Core.Geonames
  alias Bilimbi.Core.Geonames.Importer
  alias Ecto.Adapters.SQL

  import Bilimbi.Core.Geonames.TestFixtures

  setup do
    create_geonames_tables!()

    directory =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-geonames-importer-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    %{directory: directory}
  end

  test "streams canonical country, admin1, city, and postcode files", %{directory: directory} do
    country_path = write!(directory, "countryInfo.txt", country_file("Malaysia"))
    admin1_path = write!(directory, "admin1.txt", admin1_file("Kuala Lumpur"))
    city_path = write!(directory, "cities.txt", city_file("Kuala Lumpur"))
    postcode_path = write!(directory, "MY.txt", postcode_file("50000", "Kuala Lumpur"))

    assert {:ok, %{imported: 1, skipped: 2}} = Importer.countries(country_path)
    assert {:ok, %{imported: 1, skipped: 1}} = Importer.admin1(admin1_path)
    assert {:ok, %{imported: 1, skipped: 1}} = Importer.cities(city_path)
    assert {:ok, %{imported: 1, skipped: 1}} = Importer.postcodes("my", postcode_path)

    assert Geonames.get_country("MY").country == "Malaysia"
    assert [%{code: "MY.14"}] = Geonames.list_admin1("MY")
    assert Geonames.get_city_by_geoname_id(1_735_161).timezone == "Asia/Kuala_Lumpur"
    assert [%{place_name: "Kuala Lumpur"}] = Geonames.lookup_postcode("MY", "50000")

    assert [[1_733_046]] =
             SQL.query!(Repo, "SELECT geoname_id FROM geonames_admin1 WHERE code = 'MY.14'", []).rows
  end

  test "country and admin1 refreshes preserve locally edited names", %{directory: directory} do
    country_path = write!(directory, "countryInfo.txt", country_file("Malaysia"))
    admin1_path = write!(directory, "admin1.txt", admin1_file("Kuala Lumpur"))

    assert {:ok, _result} = Importer.countries(country_path)
    assert {:ok, _result} = Importer.admin1(admin1_path)

    SQL.query!(
      Repo,
      "UPDATE geonames_countries SET country = 'Malaysia Local' WHERE iso = 'MY'",
      []
    )

    SQL.query!(Repo, "UPDATE geonames_admin1 SET name = 'KL Local' WHERE code = 'MY.14'", [])

    write!(directory, "countryInfo.txt", country_file("Malaysia Upstream"))
    write!(directory, "admin1.txt", admin1_file("Kuala Lumpur Upstream"))

    assert {:ok, _result} = Importer.countries(country_path)
    assert {:ok, _result} = Importer.admin1(admin1_path)

    assert Geonames.get_country("MY").country == "Malaysia Local"
    assert [%{name: "KL Local"}] = Geonames.list_admin1("MY")
  end

  test "postcode refresh atomically replaces one country's rows", %{directory: directory} do
    country_path = write!(directory, "countryInfo.txt", country_file("Malaysia"))
    postcode_path = write!(directory, "MY.txt", postcode_file("50000", "Kuala Lumpur"))

    assert {:ok, _result} = Importer.countries(country_path)
    assert {:ok, %{imported: 1}} = Importer.postcodes("MY", postcode_path)

    write!(directory, "MY.txt", postcode_file("88000", "Kota Kinabalu"))
    assert {:ok, %{imported: 1}} = Importer.postcodes("MY", postcode_path)

    assert Geonames.lookup_postcode("MY", "50000") == []
    assert [%{place_name: "Kota Kinabalu"}] = Geonames.lookup_postcode("MY", "88000")
  end

  test "postcode refresh rematerializes edits and operator-created rows", %{directory: directory} do
    country_path = write!(directory, "countryInfo.txt", country_file("Malaysia"))
    admin1_path = write!(directory, "admin1.txt", admin1_file("Kuala Lumpur"))
    postcode_path = write!(directory, "MY.txt", postcode_file("50000", "Kuala Lumpur"))

    assert {:ok, _result} = Importer.countries(country_path)
    assert {:ok, _result} = Importer.admin1(admin1_path)
    assert {:ok, %{imported: 1}} = Importer.postcodes("MY", postcode_path)

    source = hd(Geonames.page_postcodes(%{search: "50000"}).entries)

    assert {:ok, _updated} =
             Geonames.update_postcode(source.id, source.revision, %{
               country_iso: "MY",
               postcode: "50000",
               place_name: "Kuala Lumpur Local",
               admin1_code: "14",
               latitude: "3.139",
               longitude: "101.6869",
               accuracy: "4"
             })

    assert {:ok, _created} =
             Geonames.create_postcode(%{
               country_iso: "MY",
               postcode: "63000",
               place_name: "Cyberjaya",
               admin1_code: "14"
             })

    assert {:ok, %{imported: 1}} = Importer.postcodes("MY", postcode_path)

    assert [%{place_name: "Kuala Lumpur Local"}] =
             Geonames.lookup_postcode("MY", "50000")

    assert [%{place_name: "Cyberjaya"}] = Geonames.lookup_postcode("MY", "63000")
    assert Enum.all?(Geonames.page_postcodes().entries, &(&1.provenance == :operator))
  end

  test "a cross-country correction survives refreshes without duplicate materializations", %{
    directory: directory
  } do
    country_path = write!(directory, "countryInfo.txt", country_file("Malaysia"))
    malaysia_path = write!(directory, "MY.txt", postcode_file("50000", "Kuala Lumpur"))

    united_states_path =
      write!(directory, "US.txt", postcode_file("94105", "Upstream US", "US", "CA"))

    assert {:ok, _result} = Importer.countries(country_path)

    insert_country!(%{
      iso: "US",
      iso3: "USA",
      iso_numeric: "840",
      country: "United States",
      capital: "Washington",
      continent: "NA",
      currency_code: "USD",
      currency_name: "Dollar",
      geoname_id: 6_252_001
    })

    insert_admin1!(%{code: "US.CA", name: "California", geoname_id: 5_332_921})

    assert {:ok, %{imported: 1}} = Importer.postcodes("MY", malaysia_path)
    source = hd(Geonames.page_postcodes(%{search: "50000"}).entries)

    assert {:ok, _moved} =
             Geonames.update_postcode(source.id, source.revision, %{
               country_iso: "US",
               postcode: "95000",
               place_name: "Local California",
               admin1_code: "CA"
             })

    assert {:ok, %{imported: 1}} = Importer.postcodes("MY", malaysia_path)
    assert Geonames.lookup_postcode("MY", "50000") == []
    assert [%{place_name: "Local California"}] = Geonames.lookup_postcode("US", "95000")

    assert {:ok, %{imported: 1}} = Importer.postcodes("US", united_states_path)
    assert [%{place_name: "Local California"}] = Geonames.lookup_postcode("US", "95000")
  end

  test "postcode refresh preserves known-good rows when no valid rows are parsed", %{
    directory: directory
  } do
    country_path = write!(directory, "countryInfo.txt", country_file("Malaysia"))
    postcode_path = write!(directory, "MY.txt", postcode_file("50000", "Kuala Lumpur"))

    assert {:ok, _result} = Importer.countries(country_path)
    assert {:ok, %{imported: 1}} = Importer.postcodes("MY", postcode_path)

    write!(directory, "MY.txt", "malformed\n")
    assert {:error, :no_valid_rows} = Importer.postcodes("MY", postcode_path)

    assert [%{place_name: "Kuala Lumpur"}] = Geonames.lookup_postcode("MY", "50000")
  end

  test "postcode import rejects invalid and unknown countries", %{directory: directory} do
    path = write!(directory, "MY.txt", postcode_file("50000", "Kuala Lumpur"))

    assert {:error, {:invalid_country_iso, "Malaysia"}} =
             Importer.postcodes("Malaysia", path)

    assert {:error, {:country_not_found, "MY"}} = Importer.postcodes("MY", path)
  end

  test "default datasets reject files with no valid rows", %{directory: directory} do
    country_path = write!(directory, "countryInfo.txt", country_file("Malaysia"))
    admin1_path = write!(directory, "admin1.txt", admin1_file("Kuala Lumpur"))
    city_path = write!(directory, "cities.txt", city_file("Kuala Lumpur"))

    assert {:ok, _result} = Importer.countries(country_path)
    assert {:ok, _result} = Importer.admin1(admin1_path)
    assert {:ok, _result} = Importer.cities(city_path)

    write!(directory, "countryInfo.txt", "<html>200 OK error page</html>\n")
    write!(directory, "admin1.txt", "malformed\n")
    write!(directory, "cities.txt", "malformed\n")

    assert {:error, :no_valid_rows} = Importer.countries(country_path)
    assert {:error, :no_valid_rows} = Importer.admin1(admin1_path)
    assert {:error, :no_valid_rows} = Importer.cities(city_path)

    assert Geonames.get_country("MY").country == "Malaysia"
    assert [%{code: "MY.14"}] = Geonames.list_admin1("MY")
    assert Geonames.get_city_by_geoname_id(1_735_161).name == "Kuala Lumpur"
  end

  test "a database failure after a successful batch rolls the dataset back", %{
    directory: directory
  } do
    valid_rows =
      for index <- 0..500 do
        iso = <<?A + div(index, 26), ?A + rem(index, 26)>>
        numeric = String.pad_leading(Integer.to_string(index), 3, "0")

        "#{iso}\t#{iso}S\t#{numeric}\t#{iso}\tCountry #{index}\tCapital\t1\t1\tAS\t.t\tX\tY\t1\t\t\ten\t#{index + 1}\t\n"
      end

    invalid_iso_row =
      "TOOLONG\tTOL\t999\tTL\tBad\tCapital\t1\t1\tAS\t.t\tX\tY\t1\t\t\ten\t9999999\t\n"

    path = write!(directory, "countryInfo.txt", Enum.join(valid_rows ++ [invalid_iso_row], "\n"))

    assert {:error, {:database, _message}} = Importer.countries(path)
    assert Geonames.list_countries() == []
  end

  defp country_file(name) do
    """
    # ISO\tISO3\tISO numeric\tFIPS\tCountry
    MY\tMYS\t458\tMY\t#{name}\tKuala Lumpur\t329847\t34100000\tAS\t.my\tMYR\tRinggit\t60\t#####\t^[0-9]{5}$\tms,en\t1733045\tSG,TH\t
    malformed
    """
  end

  defp admin1_file(name) do
    "MY.14\t#{name}\tKuala Lumpur\t1733046\nmalformed\n"
  end

  defp city_file(name) do
    "1735161\t#{name}\tKuala Lumpur\tKL\t3.1412\t101.6865\tP\tPPLC\tMY\t\t14\t\t\t\t1453975\t\t22\tAsia/Kuala_Lumpur\t2026-01-02\nmalformed\n"
  end

  defp postcode_file(postcode, place_name, country_iso \\ "MY", admin_code \\ "14") do
    "#{country_iso}\t#{postcode}\t#{place_name}\tAdmin1\t#{admin_code}\t\t\t\t\t3.139\t101.6869\t4\nmalformed\n"
  end

  defp write!(directory, filename, contents) do
    path = Path.join(directory, filename)
    File.write!(path, contents)
    path
  end
end
