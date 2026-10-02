defmodule Bilimbi.Base.Artifacts.PDF.Renderer do
  @moduledoc """
  Pure, deterministic PDF serializer for owner-selected business documents.

  Call `render/1` from an authorized `Bilimbi.Base.Artifacts.PDF` adapter.
  Input is `%{title: text, blocks: blocks, metadata: metadata}`. Blocks are
  `{:text, text}`, `{:table, headers, rows}`, or `:page_break`; all cells are
  strings. Metadata optionally contains `:author`, `:subject`, and `:keywords`.
  No dates, random identifiers, resources, IO, or business data are added.

  A4 pages use built-in Courier at 10 points, 85 characters per line and 48
  lines per page. Text and cells wrap without truncation; table headers repeat
  on continuation pages. A row that fits a page stays together; larger rows
  continue across pages. Explicit breaks do not create empty trailing pages.

  Body text supports printable ASCII and Latin-1 (U+00A0–U+00FF). Newlines
  break lines and tabs become spaces. Other characters return
  `{:error, :unsupported_text}` rather than producing incorrect glyphs.
  Metadata supports UTF-8 via PDF UTF-16 strings. Invalid document shapes
  return `{:error, :invalid_document}` without echoing document contents.
  This is a simple text/table renderer, not a Unicode font or HTML engine.
  """

  @columns 85
  @lines 48
  @type block :: {:text, String.t()} | {:table, [String.t()], [[String.t()]]} | :page_break
  @type document :: %{
          required(:title) => String.t(),
          required(:blocks) => [block()],
          optional(:metadata) => %{optional(:author | :subject | :keywords) => String.t()}
        }

  @spec render(document()) :: {:ok, binary()} | {:error, :invalid_document | :unsupported_text}
  def render(document) do
    validate_document!(document)
    state = append_lines({[], [], 0}, wrap(document.title, @columns))
    state = Enum.reduce(document.blocks, state, &block/2)
    {pages, current, _count} = state
    pages = Enum.reverse([Enum.reverse(current) | pages])
    pages = if length(pages) > 1 and List.last(pages) == [], do: Enum.drop(pages, -1), else: pages
    {:ok, serialize(pages, document.title, Map.get(document, :metadata, %{}))}
  catch
    {:invalid_pdf_document, reason} -> {:error, reason}
  end

  defp validate_document!(%{title: title, blocks: blocks} = document)
       when is_binary(title) and is_list(blocks) do
    require!(Enum.all?(Map.keys(document), &(&1 in [:title, :blocks, :metadata])))
    metadata = Map.get(document, :metadata, %{})
    require!(is_map(metadata) and not is_struct(metadata))

    Enum.each(metadata, fn {key, value} ->
      require!(
        key in [:author, :subject, :keywords] and is_binary(value) and String.valid?(value)
      )
    end)
  end

  defp validate_document!(_), do: invalid!(:invalid_document)

  defp block({:text, text}, state) when is_binary(text),
    do: append_lines(state, wrap(text, @columns))

  defp block(:page_break, state), do: new_page(state)

  defp block({:table, headers, rows}, state) when is_list(headers) and is_list(rows) do
    count = length(headers)
    require!(count in 1..20)
    width = div(@columns - 3 * (count - 1), count)
    heading = table_row(headers, count, width)
    require!(length(heading) < @lines)
    header = heading ++ [String.duplicate("-", count * width + 3 * (count - 1))]
    require!(length(header) < @lines)

    first_row_size =
      if rows == [],
        do: 0,
        else: min(length(table_row(hd(rows), count, width)), @lines - length(header))

    state = ensure_space(state, length(header) + first_row_size)
    state = append_lines(state, header)

    Enum.reduce(rows, state, fn row, state ->
      lines = table_row(row, count, width)
      capacity = @lines - length(header)
      {_, _, used} = state

      state =
        if length(lines) <= capacity and used + length(lines) > @lines,
          do: append_lines(new_page(state), header),
          else: state

      table_lines(state, lines, header)
    end)
  end

  defp block(_, _state), do: invalid!(:invalid_document)

  defp table_row(cells, count, width) do
    require!(is_list(cells) and length(cells) == count)
    columns = Enum.map(cells, &wrap(&1, width))
    height = columns |> Enum.map(&length/1) |> Enum.max()

    for index <- 0..(height - 1) do
      Enum.map_join(columns, " | ", fn column ->
        column |> Enum.at(index, "") |> String.pad_trailing(width)
      end)
    end
  end

  defp table_lines(state, [], _header), do: state

  defp table_lines({_, _, @lines} = state, lines, header),
    do: table_lines(append_lines(new_page(state), header), lines, header)

  defp table_lines(state, [line | rest], header),
    do: table_lines(append_line(state, line), rest, header)

  defp ensure_space({_, _, used} = state, needed) when used + needed > @lines,
    do: new_page(state)

  defp ensure_space(state, _needed), do: state

  defp new_page({pages, [], 0}), do: {pages, [], 0}
  defp new_page({pages, current, _count}), do: {[Enum.reverse(current) | pages], [], 0}
  defp append_lines(state, lines), do: Enum.reduce(lines, state, &append_line(&2, &1))
  defp append_line({_, _, @lines} = state, line), do: append_line(new_page(state), line)
  defp append_line({pages, current, count}, line), do: {pages, [line | current], count + 1}

  defp wrap(text, width) when is_binary(text) do
    require!(String.valid?(text))

    Enum.each(String.to_charlist(text), fn char ->
      if char not in [9, 10, 13] and char not in 32..126 and char not in 160..255,
        do: invalid!(:unsupported_text)
    end)

    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace("\t", " ")
    |> String.split("\n")
    |> Enum.flat_map(fn
      "" ->
        [""]

      line ->
        line |> String.to_charlist() |> Enum.chunk_every(width) |> Enum.map(&List.to_string/1)
    end)
  end

  defp wrap(_, _width), do: invalid!(:invalid_document)

  # One encoding/escaping seam for all content operands; no caller can inject
  # PDF syntax. Fixed font metrics keep every wrapped table cell within A4.
  defp literal(text) do
    text
    |> :unicode.characters_to_binary(:utf8, :latin1)
    |> :binary.bin_to_list()
    |> Enum.map(fn
      char when char in [?\\, ?(, ?)] -> [?\\, char]
      char -> char
    end)
  end

  defp info_string(text) do
    encoded = :unicode.characters_to_binary(text, :utf8, {:utf16, :big})
    ["<FEFF", Base.encode16(encoded), ">"]
  end

  defp serialize(pages, title, metadata) do
    count = length(pages)
    page_ids = for n <- 0..(count - 1), do: 5 + n * 2

    info =
      Enum.map(
        [{:title, "Title"}, {:author, "Author"}, {:subject, "Subject"}, {:keywords, "Keywords"}],
        fn {key, name} ->
          case if(key == :title, do: title, else: Map.get(metadata, key)) do
            nil -> []
            value -> [" /", name, " ", info_string(value)]
          end
        end
      )

    objects =
      [
        "<< /Type /Catalog /Pages 2 0 R >>",
        [
          "<< /Type /Pages /Count ",
          Integer.to_string(count),
          " /Kids [",
          Enum.map(page_ids, &[Integer.to_string(&1), " 0 R "]),
          "] >>"
        ],
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
        ["<<", info, " >>"]
      ] ++
        Enum.flat_map(Enum.with_index(pages), fn {page, n} ->
          stream =
            IO.iodata_to_binary([
              "BT /F1 10 Tf 40 800 Td 15 TL\n",
              Enum.map(page, &["(", literal(&1), ") Tj T*\n"]),
              "ET\n"
            ])

          [
            [
              "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ",
              Integer.to_string(6 + n * 2),
              " 0 R >>"
            ],
            [
              "<< /Length ",
              Integer.to_string(byte_size(stream)),
              " >>\nstream\n",
              stream,
              "endstream"
            ]
          ]
        end)

    {chunks, offsets, size} =
      Enum.reduce(Enum.with_index(objects, 1), {["%PDF-1.4\n"], [], 9}, fn {object, id},
                                                                           {chunks, offsets, size} ->
        chunk = [Integer.to_string(id), " 0 obj\n", object, "\nendobj\n"]
        {[chunk | chunks], [size | offsets], size + IO.iodata_length(chunk)}
      end)

    IO.iodata_to_binary([
      Enum.reverse(chunks),
      "xref\n0 ",
      Integer.to_string(length(objects) + 1),
      "\n0000000000 65535 f \n",
      Enum.map(
        Enum.reverse(offsets),
        &[String.pad_leading(Integer.to_string(&1), 10, "0"), " 00000 n \n"]
      ),
      "trailer\n<< /Size ",
      Integer.to_string(length(objects) + 1),
      " /Root 1 0 R /Info 4 0 R >>\nstartxref\n",
      Integer.to_string(size),
      "\n%%EOF\n"
    ])
  end

  defp require!(true), do: :ok
  defp require!(false), do: invalid!(:invalid_document)
  defp invalid!(reason), do: throw({:invalid_pdf_document, reason})
end
