defmodule Bilimbi.Base.Artifacts.PDF.RendererTest do
  use ExUnit.Case, async: true
  alias Bilimbi.Base.Artifacts.PDF.Renderer

  test "deterministic complete bytes, with title and ordered metadata" do
    document = %{
      title: "Record summary",
      metadata: %{subject: "Review", author: "Module author"},
      blocks: [{:text, "Frozen facts"}, {:table, ["Record", "Value"], [["A", "12.50"]]}]
    }

    assert {:ok, pdf} = Renderer.render(document)
    assert {:ok, ^pdf} = Renderer.render(document)

    assert {:ok, ^pdf} =
             Renderer.render(%{
               document
               | metadata: Map.new(Enum.reverse(Map.to_list(document.metadata)))
             })

    assert String.starts_with?(pdf, "%PDF-1.4\n")
    assert String.ends_with?(pdf, "%%EOF\n")
    assert pdf =~ "/Title <FEFF005200650063006F00720064002000730075006D006D006100720079>"
    assert pdf =~ "/Subject <FEFF005200650076006900650077>"
    assert_valid_structure(pdf)
  end

  test "hostile text is escaped in titles, text blocks and table cells" do
    hostile = "\\) Tj ET (attack)"

    assert {:ok, pdf} =
             Renderer.render(%{
               title: hostile,
               metadata: %{subject: hostile <> "\n/JavaScript"},
               blocks: [{:text, hostile}, {:table, [hostile], [[hostile]]}]
             })

    assert length(:binary.matches(pdf, "\\\\\\) Tj ET \\(attack\\)")) == 4
    assert pdf =~ "/Subject <FEFF"
    refute pdf =~ "\n/JavaScript"
    assert_valid_structure(pdf)
  end

  test "multi-page tables preserve rows, repeat headers and stay within page bounds" do
    rows =
      for n <- 1..130,
          do: ["record-#{String.pad_leading(Integer.to_string(n), 3, "0")}", "value-#{n}"]

    assert {:ok, pdf} =
             Renderer.render(%{
               title: "Records",
               blocks: [{:text, "Introduction"}, {:table, ["Record", "Value"], rows}]
             })

    assert length(streams(pdf)) == 3
    assert pdf =~ "/Count 3"

    Enum.each(streams(pdf), fn page ->
      assert page =~ "Record"
      assert page =~ "Value"
      assert length(:binary.matches(page, ") Tj T*")) <= 48
    end)

    Enum.each(rows, fn [record, value] ->
      assert length(:binary.matches(pdf, record)) == 1
      assert pdf =~ value
    end)

    assert_valid_structure(pdf)
  end

  test "rows stay together when they fit and oversized cells continue with headers" do
    assert {:ok, pdf} =
             Renderer.render(%{
               title: "Report",
               blocks: [
                 {:text, Enum.map_join(1..42, "\n", fn _ -> "Preface" end)},
                 {:table, ["Record"],
                  [[String.duplicate("x", 85 * 6)], [String.duplicate("z", 85 * 100)]]}
               ]
             })

    pages = streams(pdf)
    assert length(pages) == 4
    refute hd(pages) =~ "xxxxx"
    refute hd(pages) =~ "Record"
    assert length(:binary.matches(Enum.at(pages, 1), String.duplicate("x", 85))) == 6
    assert length(:binary.matches(pdf, String.duplicate("z", 85))) == 100
    Enum.each(tl(pages), &assert(&1 =~ "Record"))
    Enum.each(pages, &assert(length(:binary.matches(&1, ") Tj T*")) <= 48))
    assert_valid_structure(pdf)
  end

  test "wraps without truncating and avoids empty pages from explicit breaks" do
    assert {:ok, pdf} =
             Renderer.render(%{
               title: "",
               blocks: [
                 {:text, "\r\n" <> String.duplicate("a", 86) <> "\tend"},
                 :page_break,
                 :page_break,
                 {:text, "Second"},
                 :page_break
               ]
             })

    assert length(streams(pdf)) == 2
    assert pdf =~ "(#{String.duplicate("a", 85)}) Tj"
    assert pdf =~ "(a end) Tj"
    assert pdf =~ "() Tj"
    assert_valid_structure(pdf)
    assert {:ok, empty} = Renderer.render(%{title: "", blocks: []})
    assert length(streams(empty)) == 1
    assert_valid_structure(empty)
  end

  test "Latin-1 font bytes and Unicode metadata; unsupported body characters fail explicitly" do
    assert {:ok, pdf} = Renderer.render(%{title: "Café", metadata: %{author: "作者"}, blocks: []})
    assert pdf =~ <<"Caf", 233>>
    assert pdf =~ "/WinAnsiEncoding"
    assert pdf =~ "/Author <FEFF4F5C8005>"
    assert_valid_structure(pdf)

    for text <- ["作者", "emoji 😀", <<0>>, <<27>>, <<127>>, "\u0080"] do
      assert {:error, :unsupported_text} = Renderer.render(%{title: text, blocks: []})
    end
  end

  test "malformed documents fail without exposing contents" do
    for document <- [
          nil,
          %{},
          %{title: "a"},
          %{title: <<255>>, blocks: []},
          %{title: "a", blocks: [], metadata: nil},
          %{title: "a", blocks: [], metadata: %{unexpected: "sensitive"}},
          %{title: "a", blocks: [{:text, 12}]},
          %{title: "a", blocks: [{:table, [], []}]},
          %{title: "a", blocks: [{:table, ["a"], [["b", "c"]]}]},
          %{title: "a", blocks: [{:table, ["a"], [nil]}]},
          %{title: "a", blocks: [{:table, [String.duplicate("a", 85 * 48)], []}]}
        ] do
      assert {:error, :invalid_document} = Renderer.render(document)
    end
  end

  defp streams(pdf),
    do: Regex.scan(~r/stream\n(.*?)endstream/s, pdf, capture: :all_but_first) |> List.flatten()

  # Validate PDF byte addresses/lengths, including non-UTF-8 font bytes.
  defp assert_valid_structure(pdf) do
    [start] = Regex.run(~r/startxref\n(\d+)\n%%EOF/, pdf, capture: :all_but_first)
    start = String.to_integer(start)
    assert binary_part(pdf, start, 4) == "xref"
    xref = binary_part(pdf, start, byte_size(pdf) - start)
    offsets = Regex.scan(~r/(\d{10}) 00000 n/, xref, capture: :all_but_first) |> List.flatten()

    for {offset, id} <- Enum.with_index(offsets, 1) do
      prefix = "#{id} 0 obj\n"
      assert binary_part(pdf, String.to_integer(offset), byte_size(prefix)) == prefix
    end

    for [length, content] <-
          Regex.scan(~r/\/Length (\d+) >>\nstream\n(.*?)endstream/s, pdf, capture: :all_but_first) do
      assert String.to_integer(length) == byte_size(content)
    end
  end
end
