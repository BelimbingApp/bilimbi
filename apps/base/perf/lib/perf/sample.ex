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

  def changeset(sample, attrs) do
    sample
    |> cast(attrs, @fields)
    |> validate_required([:kind, :identity, :outcome, :duration_ms, :observed_at])
    |> validate_inclusion(:kind, ~w(request job runtime))
    |> validate_inclusion(:outcome, ~w(ok error cancelled discarded))
    |> validate_length(:identity, min: 1, max: 255)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:db_duration_ms, greater_than_or_equal_to: 0)
    |> validate_number(:db_count, greater_than_or_equal_to: 0)
    |> validate_number(:memory_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:run_queue, greater_than_or_equal_to: 0)
  end
end
