defmodule Bilimbi.Core.Geonames.SchemaContract do
  @moduledoc """
  Pinned PostgreSQL contract for the Core Geonames compatibility baseline.
  """

  @behaviour Bilimbi.Base.Database.SchemaContract

  @migration_version 20_260_812_103_801

  def migration_version, do: @migration_version

  @impl true
  def tables, do: [countries(), admin1(), postcodes(), cities()]

  defp countries do
    %{
      name: "geonames_countries",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "geonames_countries_id_seq"}),
        "iso" => column({:varchar, 2}, false),
        "iso3" => column({:varchar, 3}, false),
        "iso_numeric" => column({:varchar, 3}, false),
        "country" => column({:varchar, 255}, false),
        "capital" => column({:varchar, 255}),
        "area" => column(:double_precision),
        "population" => column(:bigint, false, {:integer, 0}),
        "continent" => column({:varchar, 2}, false),
        "tld" => column({:varchar, 3}),
        "currency_code" => column({:varchar, 3}),
        "currency_name" => column({:varchar, 32}),
        "phone" => column({:varchar, 24}),
        "postal_code_format" => column({:varchar, 100}),
        "postal_code_regex" => column(:text),
        "languages" => column({:varchar, 255}),
        "geoname_id" => column(:integer),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "geonames_countries_pkey" => index(["id"], true),
        "geonames_countries_iso_unique" => index(["iso"], true),
        "geonames_countries_iso3_unique" => index(["iso3"], true),
        "geonames_countries_iso_numeric_unique" => index(["iso_numeric"], true),
        "geonames_countries_continent_index" => index(["continent"]),
        "geonames_countries_geoname_id_unique" => index(["geoname_id"], true)
      },
      foreign_keys: %{}
    }
  end

  defp admin1 do
    %{
      name: "geonames_admin1",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "geonames_admin1_id_seq"}),
        "code" => column({:varchar, 20}, false),
        "name" => column({:varchar, 255}, false),
        "alt_name" => column({:varchar, 255}),
        "geoname_id" => column(:integer),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "geonames_admin1_pkey" => index(["id"], true),
        "geonames_admin1_code_unique" => index(["code"], true),
        "geonames_admin1_geoname_id_unique" => index(["geoname_id"], true)
      },
      foreign_keys: %{}
    }
  end

  defp postcodes do
    %{
      name: "geonames_postcodes",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "geonames_postcodes_id_seq"}),
        "country_iso" => column({:varchar, 2}, false),
        "postcode" => column({:varchar, 20}, false),
        "place_name" => column({:varchar, 180}, false),
        "admin1Code" => column({:varchar, 20}),
        "admin_name1" => column({:varchar, 100}),
        "admin_code1" => column({:varchar, 20}),
        "admin_name2" => column({:varchar, 100}),
        "admin_code2" => column({:varchar, 20}),
        "admin_name3" => column({:varchar, 100}),
        "admin_code3" => column({:varchar, 20}),
        "latitude" => column({:numeric, 10, 7}),
        "longitude" => column({:numeric, 10, 7}),
        "accuracy" => column(:smallint),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "geonames_postcodes_pkey" => index(["id"], true),
        "geonames_postcodes_country_iso_index" => index(["country_iso"]),
        "geonames_postcodes_postcode_index" => index(["postcode"]),
        "geonames_postcodes_place_name_index" => index(["place_name"]),
        "geonames_postcodes_admin1code_index" => index(["admin1Code"]),
        "geonames_postcodes_country_iso_postcode_index" => index(["country_iso", "postcode"]),
        "geonames_postcodes_country_iso_place_name_index" => index(["country_iso", "place_name"])
      },
      foreign_keys: %{
        "geonames_postcodes_country_iso_foreign" =>
          foreign_key("country_iso", "geonames_countries", "iso", :restrict, :cascade)
      }
    }
  end

  defp cities do
    %{
      name: "geonames_cities",
      columns: %{
        "id" => column(:bigint, false, {:sequence, "geonames_cities_id_seq"}),
        "geoname_id" => column(:integer, false),
        "name" => column({:varchar, 200}, false),
        "ascii_name" => column({:varchar, 200}, false),
        "alternate_names" => column(:text),
        "latitude" => column({:numeric, 10, 7}, false),
        "longitude" => column({:numeric, 10, 7}, false),
        "country_iso" => column({:varchar, 2}, false),
        "admin1_code" => column({:varchar, 20}),
        "population" => column(:bigint, false, {:integer, 0}),
        "timezone" => column({:varchar, 40}, false),
        "modification_date" => column(:date),
        "created_at" => column({:timestamp, 0}),
        "updated_at" => column({:timestamp, 0})
      },
      indexes: %{
        "geonames_cities_pkey" => index(["id"], true),
        "geonames_cities_geoname_id_unique" => index(["geoname_id"], true),
        "geonames_cities_country_iso_index" => index(["country_iso"]),
        "geonames_cities_admin1_code_index" => index(["admin1_code"]),
        "geonames_cities_timezone_index" => index(["timezone"])
      },
      foreign_keys: %{
        "geonames_cities_country_iso_foreign" =>
          foreign_key("country_iso", "geonames_countries", "iso", :restrict, :cascade)
      }
    }
  end

  defp column(type, nullable \\ true, default \\ nil) do
    %{type: type, nullable: nullable, default: default}
  end

  defp index(columns, unique \\ false), do: %{columns: columns, unique: unique, where: nil}

  defp foreign_key(column, table, target_column, on_delete, on_update) do
    %{
      columns: [column],
      references: {table, [target_column]},
      on_delete: on_delete,
      on_update: on_update
    }
  end
end
