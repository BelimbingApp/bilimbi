defmodule Bilimbi.Base.Perf.Sample do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "base_perf_samples" do
    field(:kind, :string)
    field(:identity, :string)
    field(:outcome, :string)
    field(:duration_ms, :integer)
    field(:db_duration_ms, :integer, default: 0)
    field(:db_count, :integer, default: 0)
    field(:response_size_class, :string)
    field(:memory_bytes, :integer)
    field(:run_queue, :integer)
    field(:observed_at, :utc_datetime_usec)
  end

  @fields [
    :kind,
    :identity,
    :outcome,
    :duration_ms,
    :db_duration_ms,
    :db_count,
    :response_size_class,
    :memory_bytes,
    :run_queue,
    :observed_at
  ]
  @route_pattern ~r|^/[A-Za-z0-9_/:.*-]{0,254}$|
  @live_view_pattern ~r|^liveview:Elixir\.[A-Za-z0-9_.]{1,230}$|
  @worker_pattern ~r|^[a-z0-9][a-z0-9_/-]{0,127}$|

  def changeset(sample, attrs) do
    sample
    |> cast(attrs, @fields)
    |> validate_required([:kind, :identity, :outcome, :duration_ms, :observed_at])
    |> validate_inclusion(:kind, ~w(request liveview job runtime))
    |> validate_inclusion(:outcome, ~w(ok error cancelled discarded))
    |> validate_inclusion(:response_size_class, ~w(under_1k 1k_10k 10k_100k over_100k))
    |> validate_length(:identity, min: 1, max: 255)
    |> validate_identity()
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:db_duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:db_count, greater_than_or_equal_to: 0)
    |> validate_number(:memory_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:run_queue, greater_than_or_equal_to: 0)
  end

  defp validate_identity(changeset) do
    validate_change(changeset, :identity, fn :identity, identity ->
      valid? =
        case get_field(changeset, :kind) do
          "request" ->
            Regex.match?(@route_pattern, identity) and not String.contains?(identity, "?")

          "liveview" ->
            Regex.match?(@live_view_pattern, identity)

          "job" ->
            Regex.match?(@worker_pattern, identity)

          "runtime" ->
            identity == "beam"

          _unknown ->
            false
        end

      if valid?, do: [], else: [identity: "is not a permitted stable identity"]
    end)
  end
end
