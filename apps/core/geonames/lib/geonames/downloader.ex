defmodule Bilimbi.Core.Geonames.Downloader do
  @moduledoc false

  @default_ttl_days 7
  @default_connect_timeout 10_000
  @default_receive_timeout 300_000

  @typedoc """
  `:status` is the HTTP status, `nil` for a cache hit that made no request, or
  `{:fallback, cause}` when a failed download reused the existing local file.
  The cause is kept because "the server refused" and "the server was
  unreachable" are different things to tell an operator (#273).
  """
  @type result :: %{
          path: String.t(),
          cached: boolean(),
          status: non_neg_integer() | nil | {:fallback, fallback_cause()},
          etag: String.t() | nil,
          cached_at: DateTime.t() | nil
        }

  @type fallback_cause :: :unreachable | {:http_status, non_neg_integer()}

  @spec download(String.t(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def download(url, destination, opts \\ []) when is_binary(url) and is_binary(destination) do
    ttl_days = Keyword.get(opts, :ttl_days, @default_ttl_days)
    force? = Keyword.get(opts, :force, false)
    etag_path = destination <> ".etag"

    with :ok <- File.mkdir_p(Path.dirname(destination)) do
      if not force? and fresh_without_etag?(destination, etag_path, ttl_days) do
        {:ok, cached_result(destination, nil, nil)}
      else
        request(url, destination, etag_path, force?, opts)
      end
    end
  end

  defp request(url, destination, etag_path, force?, opts) do
    stored_etag =
      if force? or not File.regular?(destination), do: nil, else: read_etag(etag_path)

    temporary_path = destination <> ".download-#{System.unique_integer([:positive])}"
    headers = if stored_etag, do: [{"if-none-match", stored_etag}], else: []
    connect_options = [timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout)]

    request_options =
      opts
      |> Keyword.get(:req_options, [])
      |> Keyword.merge(
        url: url,
        headers: headers,
        into: File.stream!(temporary_path, [:write]),
        connect_options: connect_options,
        receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
        retry: false
      )

    # Only transport failures become a fallback. A blanket `rescue` also swallows
    # our own bugs -- a malformed request option would be served from cache and
    # look like a working page (#273).
    response =
      try do
        Req.get(request_options)
      rescue
        exception in [Mint.TransportError, Mint.HTTPError, Req.TransportError] ->
          {:error, exception}
      end

    case response do
      {:ok, %Req.Response{status: 304}} when not is_nil(stored_etag) ->
        File.rm(temporary_path)
        {:ok, cached_result(destination, 304, stored_etag)}

      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        etag = response |> Req.Response.get_header("etag") |> List.first()

        with :ok <- replace_file(temporary_path, destination),
             :ok <- store_etag(etag_path, etag) do
          {:ok, %{path: destination, cached: false, status: status, etag: etag}}
        end

      {:ok, %Req.Response{status: status}} ->
        File.rm(temporary_path)

        if not force? and status in [500, 502, 503, 504, 429] and valid_cached_file?(destination) do
          {:ok, cached_result(destination, {:fallback, {:http_status, status}}, stored_etag)}
        else
          {:error, {:http_status, status}}
        end

      {:error, exception} ->
        File.rm(temporary_path)

        if not force? and valid_cached_file?(destination) do
          {:ok, cached_result(destination, {:fallback, :unreachable}, stored_etag)}
        else
          {:error, {:request, exception}}
        end
    end
  end

  defp valid_cached_file?(destination) do
    case File.stat(destination) do
      {:ok, %{size: size}} when size > 0 -> true
      _other -> false
    end
  end

  # How old the data we fell back to actually is. Reported rather than used to
  # refuse: a hard age bound would turn an unreachable server into a failed
  # screen, which is the resilience this feature exists to provide. Telling the
  # operator the date lets them judge (#273).
  defp cached_at(destination) do
    case File.stat(destination, time: :posix) do
      {:ok, %{mtime: mtime}} -> DateTime.from_unix!(mtime)
      _other -> nil
    end
  end

  defp fresh_without_etag?(destination, etag_path, ttl_days)
       when is_integer(ttl_days) and ttl_days >= 0 do
    with true <- File.regular?(destination),
         false <- File.regular?(etag_path),
         {:ok, %{mtime: modified_at}} <- File.stat(destination, time: :posix) do
      modified_at >= System.os_time(:second) - ttl_days * 86_400
    else
      _other -> false
    end
  end

  defp fresh_without_etag?(_destination, _etag_path, _ttl_days), do: false

  defp read_etag(path) do
    case File.read(path) do
      {:ok, contents} ->
        case String.trim(contents) do
          "" -> nil
          etag -> etag
        end

      {:error, _reason} ->
        nil
    end
  end

  defp store_etag(path, nil), do: File.rm(path) |> normalize_rm()
  defp store_etag(path, etag), do: File.write(path, etag)

  defp normalize_rm(:ok), do: :ok
  defp normalize_rm({:error, :enoent}), do: :ok
  defp normalize_rm(error), do: error

  defp replace_file(source, destination) do
    case File.rename(source, destination) do
      :ok ->
        :ok

      {:error, :eexist} ->
        with :ok <- File.rm(destination), do: File.rename(source, destination)

      error ->
        error
    end
  end

  defp cached_result(path, status, etag) do
    %{path: path, cached: true, status: status, etag: etag, cached_at: cached_at(path)}
  end
end
