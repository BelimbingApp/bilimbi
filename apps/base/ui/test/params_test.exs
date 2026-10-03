defmodule Bilimbi.Base.UI.ParamsTest do
  use ExUnit.Case, async: true

  alias Bilimbi.Base.UI.Params

  describe "positive_integer/2" do
    test "keeps a positive integer and trims a decimal string" do
      assert Params.positive_integer(25, 1) == 25
      assert Params.positive_integer(" 50 ", 1) == 50
      assert Params.positive_integer("+7", 1) == 7
    end

    test "returns the default for blank, zero, negative, and partial parses" do
      assert Params.positive_integer(nil, 1) == 1
      assert Params.positive_integer("", 1) == 1
      assert Params.positive_integer("  ", 1) == 1
      assert Params.positive_integer("0", 1) == 1
      assert Params.positive_integer(0, 1) == 1
      assert Params.positive_integer("-3", 1) == 1
      assert Params.positive_integer("25abc", 1) == 1
      assert Params.positive_integer("1.5", 1) == 1
      assert Params.positive_integer(:nope, 1) == 1
      assert Params.positive_integer("x") == nil
    end
  end

  describe "positive_id/1" do
    test "accepts a positive integer and rejects everything else" do
      assert Params.positive_id(12) == {:ok, 12}
      assert Params.positive_id(" 12 ") == {:ok, 12}
      assert Params.positive_id(nil) == :error
      assert Params.positive_id("0") == :error
      assert Params.positive_id("-1") == :error
      assert Params.positive_id("12abc") == :error
    end
  end

  describe "blank_to_nil/1 and trimmed/1" do
    test "blank is only nil and the empty string" do
      assert Params.blank_to_nil(nil) == nil
      assert Params.blank_to_nil("") == nil
      assert Params.blank_to_nil(" ") == " "
      assert Params.blank_to_nil("kept") == "kept"
    end

    test "trimmed leaves a non-binary alone" do
      assert Params.trimmed("  a  ") == "a"
      assert Params.trimmed(4) == 4
    end
  end
end
