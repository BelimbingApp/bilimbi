defmodule Bilimbi.Base.Media.Upload do
  @moduledoc false
  alias Bilimbi.Base.Settings

  @active_types ~w(image/svg+xml text/html application/xhtml+xml application/xml text/xml)

  # MIME comes from libmagic's file command against the server's temporary
  # upload, never the client filename or Plug.Upload.content_type. The command
  # receives an argument list and --; no shell or caller-selected executable.
  def read(%Plug.Upload{path: path, filename: filename}, attachment? \\ false, rules \\ %{}) do
    with {:ok, %{type: :regular, size: size}} <- File.lstat(path),
         {:ok, max} <- maximum(rules),
         true <- size > 0 and size <= max,
         {:ok, mime} <- detect(path),
         :ok <- allowed(mime, attachment?),
         :ok <- subject_type_allowed(mime, rules),
         {:ok, bytes} <- File.read(path),
         true <- byte_size(bytes) == size do
      {:ok, bytes, %{original_filename: filename, mime_type: mime, file_size: size}}
    else
      false -> {:error, :invalid_size}
      {:error, _} = error -> error
      _ -> {:error, :invalid_upload}
    end
  end

  defp maximum(rules) when is_map(rules) do
    maximum = Map.get(rules, :max_bytes, Settings.get("media.max_bytes"))
    types = Map.get(rules, :allowed_mime_types, [])

    if Map.keys(rules) -- [:max_bytes, :allowed_mime_types] == [] and
         is_integer(maximum) and maximum > 0 and is_list(types) and Enum.all?(types, &is_binary/1),
       do: {:ok, min(maximum, Settings.get("media.max_bytes"))},
       else: {:error, :invalid_rules}
  end

  defp maximum(_), do: {:error, :invalid_rules}

  defp subject_type_allowed(mime, %{allowed_mime_types: types}) do
    if mime in types, do: :ok, else: {:error, :disallowed_type}
  end

  defp subject_type_allowed(_mime, _rules), do: :ok

  def allowed(mime, attachment?) do
    types = Settings.get("media.attachment_allowed_types")

    cond do
      mime in @active_types -> {:error, :disallowed_type}
      attachment? and (not is_list(types) or mime not in types) -> {:error, :disallowed_type}
      true -> :ok
    end
  end

  defp detect(path) do
    case System.find_executable("file") do
      nil ->
        {:error, :mime_detection_unavailable}

      file ->
        case System.cmd(file, ["--brief", "--mime-type", "--", path], stderr_to_stdout: true) do
          {mime, 0} -> {:ok, String.trim(mime)}
          _ -> {:error, :invalid_upload}
        end
    end
  end
end
