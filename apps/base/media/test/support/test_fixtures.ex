defmodule Bilimbi.Base.Media.TestFixtures do
  @moduledoc false
  alias Bilimbi.Base.Database.SchemaVerifier
  alias Bilimbi.Base.Media.{Contributions, ContributionValidator, TestAuthorizer}
  alias Bilimbi.Base.ModuleRegistry.ContributionRegistry
  alias Bilimbi.Base.Repo
  @ddl Path.expand("../fixtures/legacy_media.sql", __DIR__)

  # Independent upstream DDL, not a production migration replay. The excerpt
  # is taken verbatim from Compatibility's pinned Laravel-generated schema.
  def create_media_tables!(prefix \\ Bilimbi.Base.Database.DataCase.temporary_schema!()) do
    sql =
      File.read!(@ddl)
      |> String.replace("public.", SchemaVerifier.quote_identifier!(prefix) <> ".")

    sql |> String.split(";", trim: true) |> Enum.each(&Ecto.Adapters.SQL.query!(Repo, &1, []))
  end

  def entry do
    %{
      descriptor: %{id: "domain/test", otp_app: :bilimbi_base_media, dependencies: ["base/media"]},
      payload: %{
        subjects: [
          %{key: "test.record", aliases: ["App\\Domain\\Test\\Record"], adapter: TestAuthorizer}
        ]
      }
    }
  end

  def install_registry! do
    settings =
      Bilimbi.Base.Settings.ContributionValidator.validate_contributions!([
        %{descriptor: %{id: "base/media"}, payload: Contributions.contributions().settings}
      ])

    ContributionRegistry.put_consumers_for_test!(%{
      media: ContributionValidator.validate_contributions!([entry()]),
      settings: settings
    })
  end

  def upload_file!(directory, bytes \\ "attachment contents", name \\ "evidence.txt") do
    path = Path.join(directory, Ecto.UUID.generate())
    File.write!(path, bytes)
    %Plug.Upload{path: path, filename: name, content_type: "text/html"}
  end
end
