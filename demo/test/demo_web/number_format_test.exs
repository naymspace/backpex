defmodule DemoWeb.NumberFormatTest do
  use ExUnit.Case, async: true

  alias DemoWeb.NumberFormat

  doctest DemoWeb.NumberFormat

  describe "to_delimited/1" do
    test "returns nil for nil" do
      assert NumberFormat.to_delimited(nil) == nil
    end

    test "leaves numbers below 1000 untouched" do
      assert NumberFormat.to_delimited(0) == "0"
      assert NumberFormat.to_delimited(999) == "999"
    end

    test "delimits thousands groups" do
      assert NumberFormat.to_delimited(1_000) == "1.000"
      assert NumberFormat.to_delimited(12_345) == "12.345"
      assert NumberFormat.to_delimited(1_234_567_890) == "1.234.567.890"
    end

    test "delimits negative numbers" do
      assert NumberFormat.to_delimited(-1_234) == "-1.234"
      assert NumberFormat.to_delimited(-999) == "-999"
    end

    test "rounds floats and decimals to integers" do
      assert NumberFormat.to_delimited(1_234.4) == "1.234"
      assert NumberFormat.to_delimited(1_234.6) == "1.235"
      assert NumberFormat.to_delimited(Decimal.new("1234.6")) == "1.235"
    end
  end
end
