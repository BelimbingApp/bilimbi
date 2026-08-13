defmodule Bilimbi.Core.Geonames.TestFixtures do
  @moduledoc false

  alias Bilimbi.Base.Repo
  alias Ecto.Adapters.SQL

  def create_geonames_tables! do
    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE geonames_countries (
        id bigserial PRIMARY KEY,
        iso varchar(2) NOT NULL UNIQUE,
        iso3 varchar(3) NOT NULL UNIQUE,
        iso_numeric varchar(3) NOT NULL UNIQUE,
        country varchar(255) NOT NULL,
        capital varchar(255),
        area double precision,
        population bigint NOT NULL DEFAULT 0,
        continent varchar(2) NOT NULL,
        tld varchar(3),
        currency_code varchar(3),
        currency_name varchar(32),
        phone varchar(24),
        postal_code_format varchar(100),
        postal_code_regex text,
        languages varchar(255),
        geoname_id integer UNIQUE,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE geonames_admin1 (
        id bigserial PRIMARY KEY,
        code varchar(20) NOT NULL UNIQUE,
        name varchar(255) NOT NULL,
        alt_name varchar(255),
        geoname_id integer UNIQUE,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE geonames_postcodes (
        id bigserial PRIMARY KEY,
        country_iso varchar(2) NOT NULL,
        postcode varchar(20) NOT NULL,
        place_name varchar(180) NOT NULL,
        "admin1Code" varchar(20),
        admin_name1 varchar(100),
        admin_code1 varchar(20),
        admin_name2 varchar(100),
        admin_code2 varchar(20),
        admin_name3 varchar(100),
        admin_code3 varchar(20),
        latitude numeric(10,7),
        longitude numeric(10,7),
        accuracy smallint,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        CONSTRAINT geonames_postcodes_country_iso_foreign
          FOREIGN KEY (country_iso) REFERENCES geonames_countries (iso)
          ON UPDATE CASCADE ON DELETE RESTRICT
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )

    SQL.query!(
      Repo,
      """
      CREATE TEMPORARY TABLE geonames_cities (
        id bigserial PRIMARY KEY,
        geoname_id integer NOT NULL UNIQUE,
        name varchar(200) NOT NULL,
        ascii_name varchar(200) NOT NULL,
        alternate_names text,
        latitude numeric(10,7) NOT NULL,
        longitude numeric(10,7) NOT NULL,
        country_iso varchar(2) NOT NULL,
        admin1_code varchar(20),
        population bigint NOT NULL DEFAULT 0,
        timezone varchar(40) NOT NULL,
        modification_date date,
        created_at timestamp(0) without time zone,
        updated_at timestamp(0) without time zone,
        CONSTRAINT geonames_cities_country_iso_foreign
          FOREIGN KEY (country_iso) REFERENCES geonames_countries (iso)
          ON UPDATE CASCADE ON DELETE RESTRICT
      ) ON COMMIT PRESERVE ROWS
      """,
      []
    )
  end

  def insert_country!(attributes \\ %{}) do
    attributes =
      Map.merge(
        %{
          iso: "MY",
          iso3: "MYS",
          iso_numeric: "458",
          country: "Malaysia",
          capital: "Kuala Lumpur",
          area: 329_847.0,
          population: 34_100_000,
          continent: "AS",
          phone: nil,
          currency_code: "MYR",
          currency_name: "Ringgit",
          geoname_id: 1_733_045,
          created_at: nil,
          updated_at: nil
        },
        attributes
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO geonames_countries (
        iso, iso3, iso_numeric, country, capital, area, population,
        continent, phone, currency_code, currency_name, geoname_id, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      """,
      [
        attributes.iso,
        attributes.iso3,
        attributes.iso_numeric,
        attributes.country,
        attributes.capital,
        attributes.area,
        attributes.population,
        attributes.continent,
        attributes.phone,
        attributes.currency_code,
        attributes.currency_name,
        attributes.geoname_id,
        attributes.created_at,
        attributes.updated_at
      ]
    )
  end

  def insert_admin1!(attributes \\ %{}) do
    attributes =
      Map.merge(
        %{
          code: "MY.14",
          name: "Kuala Lumpur",
          alt_name: nil,
          geoname_id: 1_733_046,
          created_at: nil,
          updated_at: nil
        },
        attributes
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO geonames_admin1 (code, name, alt_name, geoname_id, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6)
      """,
      [
        attributes.code,
        attributes.name,
        attributes.alt_name,
        attributes.geoname_id,
        attributes.created_at,
        attributes.updated_at
      ]
    )
  end

  def insert_postcode!(attributes \\ %{}) do
    attributes =
      Map.merge(
        %{
          country_iso: "MY",
          postcode: "50000",
          place_name: "Kuala Lumpur",
          admin1_code: "MY.14",
          latitude: Decimal.new("3.1390000"),
          longitude: Decimal.new("101.6869000"),
          accuracy: 4,
          created_at: nil,
          updated_at: nil
        },
        attributes
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO geonames_postcodes (
        country_iso, postcode, place_name, "admin1Code", latitude, longitude, accuracy, created_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      """,
      [
        attributes.country_iso,
        attributes.postcode,
        attributes.place_name,
        attributes.admin1_code,
        attributes.latitude,
        attributes.longitude,
        attributes.accuracy,
        attributes.created_at,
        attributes.updated_at
      ]
    )
  end

  def insert_city!(attributes \\ %{}) do
    attributes =
      Map.merge(
        %{
          geoname_id: 1_735_161,
          name: "Kuala Lumpur",
          ascii_name: "Kuala Lumpur",
          alternate_names: nil,
          latitude: Decimal.new("3.1412000"),
          longitude: Decimal.new("101.6865000"),
          country_iso: "MY",
          admin1_code: "MY.14",
          population: 1_453_975,
          timezone: "Asia/Kuala_Lumpur"
        },
        attributes
      )

    SQL.query!(
      Repo,
      """
      INSERT INTO geonames_cities (
        geoname_id, name, ascii_name, alternate_names, latitude, longitude,
        country_iso, admin1_code, population, timezone
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      """,
      [
        attributes.geoname_id,
        attributes.name,
        attributes.ascii_name,
        attributes.alternate_names,
        attributes.latitude,
        attributes.longitude,
        attributes.country_iso,
        attributes.admin1_code,
        attributes.population,
        attributes.timezone
      ]
    )
  end
end
