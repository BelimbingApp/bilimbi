defmodule Bilimbi.Base.Artifacts.PDF.Engine do
  @moduledoc false
  alias Bilimbi.Base.Settings

  # One private, bounded subprocess seam for Chromium and qpdf. Secrets and
  # content are 0600 files in a 0700 temporary directory, never argv or logs.
  # Node's standard library owns process-group cleanup; no AI/browser framework
  # or npm dependency is needed to print a document through Chromium's CDP pipe.
  def render({kind, value}) when kind in [:html, :url] and is_binary(value) do
    if byte_size(value) <= Settings.get("artifacts.max_bytes") do
      execute(
        "chromium",
        %{
          "source" => Atom.to_string(kind),
          "value" => value,
          "format" => Settings.get("pdf.paper.format"),
          "printBackground" => Settings.get("pdf.paper.print_background")
        },
        Settings.get("pdf.render_timeout_seconds")
      )
    else
      {:error, :invalid_size}
    end
  end

  def render(_), do: {:error, :invalid_html}

  def protect(bytes, password, owner_password)
      when is_binary(bytes) and is_binary(password) and password != "" and
             (is_nil(owner_password) or (is_binary(owner_password) and owner_password != "")) do
    execute(
      "qpdf",
      %{
        "bytes" => Base.encode64(bytes),
        "password" => password,
        "ownerPassword" => owner_password || password
      },
      Settings.get("pdf.qpdf.timeout_seconds")
    )
  end

  def protect(_, "", _), do: {:error, :empty_password}
  def protect(_, _, _), do: {:error, :invalid_password}

  @doc false
  def available?(tool) when tool in [:qpdf, :chromium] do
    match?({:ok, _}, executable(Settings.get("pdf.node_binary"))) and
      match?({:ok, _}, executable(Settings.get("pdf." <> Atom.to_string(tool) <> ".binary")))
  end

  @doc false
  def valid_format?(format), do: format in ["A4", "A3", "A5", "Letter", "Legal", "Tabloid"]

  defp execute(tool, params, timeout) do
    with {:ok, node} <- executable(Settings.get("pdf.node_binary")),
         {:ok, binary} <- executable(Settings.get("pdf." <> tool <> ".binary")) do
      temporary(fn dir ->
        input = Path.join(dir, "request.json")
        output = Path.join(dir, "output.pdf")

        request =
          Map.merge(params, %{
            "tool" => tool,
            "binary" => binary,
            "output" => output,
            "timeoutMs" => timeout * 1000,
            "maxBytes" => Settings.get("artifacts.max_bytes")
          })

        :ok = private_write(input, Jason.encode!(request))
        script = Application.app_dir(:bilimbi_base_artifacts, "priv/pdf/runner.mjs")

        with :ok <- run(node, script, input, timeout * 1000 + 5000),
             {:ok, stat} <- File.stat(output),
             true <- stat.size > 0 and stat.size <= request["maxBytes"],
             {:ok, <<"%PDF-", _::binary>> = bytes} <- File.read(output) do
          {:ok, bytes}
        else
          {:error, _} = error -> error
          _ -> {:error, :invalid_pdf}
        end
      end)
    end
  end

  defp executable(value) when is_binary(value) and value != "" do
    case System.find_executable(value) do
      nil -> {:error, :pdf_tool_unavailable}
      binary -> {:ok, binary}
    end
  end

  defp executable(_), do: {:error, :pdf_tool_unavailable}

  defp temporary(fun) do
    dir = Path.join(System.tmp_dir!(), "bilimbi-pdf-" <> Ecto.UUID.generate())

    try do
      with :ok <- File.mkdir(dir), :ok <- File.chmod(dir, 0o700), do: fun.(dir)
    after
      File.rm_rf(dir)
    end
  rescue
    _ -> {:error, :pdf_engine_failed}
  end

  defp private_write(path, bytes) do
    with {:ok, file} <- File.open(path, [:write, :binary, :exclusive]) do
      try do
        with :ok <- File.chmod(path, 0o600), do: IO.binwrite(file, bytes)
      after
        File.close(file)
      end
    end
  end

  defp run(node, script, input, timeout) do
    port =
      Port.open({:spawn_executable, node}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [script, input]
      ])

    deadline = System.monotonic_time(:millisecond) + timeout

    try do
      await(port, deadline)
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp await(port, deadline) do
    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, 124}} -> {:error, :pdf_timeout}
      {^port, {:exit_status, _}} -> {:error, :pdf_engine_failed}
      {^port, {:data, _discarded}} -> await(port, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :pdf_timeout}
    end
  end
end
