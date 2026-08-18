defmodule Bilimbi.Core.Geonames.DownloaderTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Core.Geonames.Downloader

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "bilimbi-geonames-downloader-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "uses a fresh cached file when no ETag is available", %{directory: directory} do
    destination = Path.join(directory, "countryInfo.txt")
    File.write!(destination, "cached")

    assert {:ok, result} =
             Downloader.download("http://127.0.0.1:1/not-requested", destination, ttl_days: 7)

    assert result.cached
    assert result.path == destination
    assert result.status == nil
    assert File.read!(destination) == "cached"
  end

  test "stores an ETag and uses a conditional request without replacing the file", %{
    directory: directory
  } do
    destination = Path.join(directory, "countryInfo.txt")
    request_count = start_supervised!({Agent, fn -> 0 end})

    Req.Test.expect(__MODULE__, 2, fn conn ->
      case Agent.get_and_update(request_count, &{&1, &1 + 1}) do
        0 ->
          conn
          |> Plug.Conn.put_resp_header("etag", ~s("v1"))
          |> Req.Test.text("fresh countries")

        1 ->
          assert {"if-none-match", ~s("v1")} in conn.req_headers

          conn
          |> Plug.Conn.put_status(304)
          |> Req.Test.text("")
      end
    end)

    req_options = [plug: {Req.Test, __MODULE__}]

    assert {:ok, first} =
             Downloader.download("https://example.test/countries", destination,
               req_options: req_options
             )

    refute first.cached
    assert first.etag == ~s("v1")
    assert File.read!(destination) == "fresh countries"

    assert {:ok, second} =
             Downloader.download("https://example.test/countries", destination,
               req_options: req_options
             )

    assert second.cached
    assert second.status == 304
    assert File.read!(destination) == "fresh countries"
  end

  test "reports HTTP failures without replacing a prior cache", %{directory: directory} do
    destination = Path.join(directory, "countryInfo.txt")
    File.write!(destination, "known good")

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.text("unavailable")
    end)

    assert {:error, {:http_status, 503}} =
             Downloader.download("https://example.test/countries", destination,
               force: true,
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    assert File.read!(destination) == "known good"
  end

  test "does not send a stale ETag when the cached payload is missing", %{directory: directory} do
    destination = Path.join(directory, "countryInfo.txt")
    File.write!(destination <> ".etag", ~s("orphaned"))

    Req.Test.expect(__MODULE__, fn conn ->
      refute Enum.any?(conn.req_headers, &match?({"if-none-match", _value}, &1))
      Req.Test.text(conn, "recovered payload")
    end)

    assert {:ok, result} =
             Downloader.download("https://example.test/countries", destination,
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    refute result.cached
    assert File.read!(destination) == "recovered payload"
  end

  test "falls back to existing valid cached file on request exception when force is false", %{
    directory: directory
  } do
    destination = Path.join(directory, "countryInfo.txt")
    File.write!(destination, "cached fallback")
    File.write!(destination <> ".etag", ~s("v1"))

    assert {:ok, result} =
             Downloader.download("https://example.test/countries", destination,
               req_options: [
                 plug: fn _conn ->
                   raise %Mint.TransportError{reason: :connect_timeout}
                 end
               ]
             )

    assert result.cached
    assert result.status == :fallback
    assert result.etag == ~s("v1")
    assert File.read!(destination) == "cached fallback"
  end

  test "falls back to existing valid cached file on 503 error when force is false", %{
    directory: directory
  } do
    destination = Path.join(directory, "countryInfo.txt")
    File.write!(destination, "cached 503 fallback")
    File.write!(destination <> ".etag", ~s("v2"))

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.text("unavailable")
    end)

    assert {:ok, result} =
             Downloader.download("https://example.test/countries", destination,
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    assert result.cached
    assert result.status == :fallback
    assert result.etag == ~s("v2")
    assert File.read!(destination) == "cached 503 fallback"
  end
end
