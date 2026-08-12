defmodule Bilimbi.Core.Geonames.Migrations.CreateCompatibilityBaseline do
  use Ecto.Migration

  def up do
    create table(:geonames_countries, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :iso, :string, size: 2, null: false
      add :iso3, :string, size: 3, null: false
      add :iso_numeric, :string, size: 3, null: false
      add :country, :string, null: false
      add :capital, :string
      add :area, :float
      add :population, :bigint, null: false, default: 0
      add :continent, :string, size: 2, null: false
      add :tld, :string, size: 3
      add :currency_code, :string, size: 3
      add :currency_name, :string, size: 32
      add :phone, :string, size: 24
      add :postal_code_format, :string, size: 100
      add :postal_code_regex, :text
      add :languages, :string
      add :geoname_id, :integer
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:geonames_countries, [:iso], name: :geonames_countries_iso_unique)
    create unique_index(:geonames_countries, [:iso3], name: :geonames_countries_iso3_unique)

    create unique_index(:geonames_countries, [:iso_numeric],
             name: :geonames_countries_iso_numeric_unique
           )

    create index(:geonames_countries, [:continent], name: :geonames_countries_continent_index)

    create unique_index(:geonames_countries, [:geoname_id],
             name: :geonames_countries_geoname_id_unique
           )

    create table(:geonames_admin1, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :code, :string, size: 20, null: false
      add :name, :string, null: false
      add :alt_name, :string
      add :geoname_id, :integer
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:geonames_admin1, [:code], name: :geonames_admin1_code_unique)

    create unique_index(:geonames_admin1, [:geoname_id], name: :geonames_admin1_geoname_id_unique)

    create table(:geonames_postcodes, primary_key: false) do
      add :id, :bigserial, primary_key: true

      add :country_iso,
          references(:geonames_countries,
            column: :iso,
            type: :string,
            on_delete: :restrict,
            on_update: :update_all,
            name: :geonames_postcodes_country_iso_foreign
          ),
          size: 2,
          null: false

      add :postcode, :string, size: 20, null: false
      add :place_name, :string, size: 180, null: false
      add :admin1Code, :string, size: 20
      add :admin_name1, :string, size: 100
      add :admin_code1, :string, size: 20
      add :admin_name2, :string, size: 100
      add :admin_code2, :string, size: 20
      add :admin_name3, :string, size: 100
      add :admin_code3, :string, size: 20
      add :latitude, :decimal, precision: 10, scale: 7
      add :longitude, :decimal, precision: 10, scale: 7
      add :accuracy, :smallint
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create index(:geonames_postcodes, [:country_iso], name: :geonames_postcodes_country_iso_index)

    create index(:geonames_postcodes, [:postcode], name: :geonames_postcodes_postcode_index)

    create index(:geonames_postcodes, [:place_name], name: :geonames_postcodes_place_name_index)

    create index(:geonames_postcodes, [:admin1Code], name: :geonames_postcodes_admin1code_index)

    create index(:geonames_postcodes, [:country_iso, :postcode],
             name: :geonames_postcodes_country_iso_postcode_index
           )

    create index(:geonames_postcodes, [:country_iso, :place_name],
             name: :geonames_postcodes_country_iso_place_name_index
           )

    create table(:geonames_cities, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :geoname_id, :integer, null: false
      add :name, :string, size: 200, null: false
      add :ascii_name, :string, size: 200, null: false
      add :alternate_names, :text
      add :latitude, :decimal, precision: 10, scale: 7, null: false
      add :longitude, :decimal, precision: 10, scale: 7, null: false

      add :country_iso,
          references(:geonames_countries,
            column: :iso,
            type: :string,
            on_delete: :restrict,
            on_update: :update_all,
            name: :geonames_cities_country_iso_foreign
          ),
          size: 2,
          null: false

      add :admin1_code, :string, size: 20
      add :population, :bigint, null: false, default: 0
      add :timezone, :string, size: 40, null: false
      add :modification_date, :date
      timestamps(type: :naive_datetime, null: true, inserted_at: :created_at)
    end

    create unique_index(:geonames_cities, [:geoname_id], name: :geonames_cities_geoname_id_unique)

    create index(:geonames_cities, [:country_iso], name: :geonames_cities_country_iso_index)
    create index(:geonames_cities, [:admin1_code], name: :geonames_cities_admin1_code_index)
    create index(:geonames_cities, [:timezone], name: :geonames_cities_timezone_index)
  end

  def down do
    drop table(:geonames_cities)
    drop table(:geonames_postcodes)
    drop table(:geonames_admin1)
    drop table(:geonames_countries)
  end
end
