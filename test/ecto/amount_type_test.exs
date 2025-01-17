defmodule Backpex.Ecto.AmountTypeTest do
  use ExUnit.Case, async: true
  alias Backpex.Ecto.Amount.Type

  describe "Ecto Amount Type Test" do
    test "type" do
      assert Type.type([]) == :integer
    end

    test "init" do
      opts = [currency: :EUR, opts: [separator: ".", delimiter: ","]]
      assert Type.init(opts) == opts
    end

    test "cast int" do
      assert Type.cast(10_000, []) == {:ok, %Money{amount: 10_000, currency: :USD}}
    end

    test "cast int with opts" do
      opts = [currency: :EUR, opts: [separator: ".", delimiter: ","]]
      assert Type.cast(10_000, opts) == {:ok, %Money{amount: 10_000, currency: :EUR}}
    end

    test "cast binary" do
      assert Type.cast("1000000", []) == {:ok, %Money{amount: 100_000_000, currency: :USD}}
    end

    test "cast binary with opts" do
      opts = [currency: :EUR, opts: [separator: ".", delimiter: ","]]
      assert Type.cast("1000000", opts) == {:ok, %Money{amount: 100_000_000, currency: :EUR}}
    end

    test "cast nil" do
      assert Type.cast(nil, currency: :EUR, opts: [separator: ".", delimiter: ","]) ==
               {:ok, %Money{amount: 0, currency: :EUR}}

      assert Type.cast(nil, []) == {:ok, %Money{amount: 0, currency: :USD}}
    end

    test "cast dirty" do
      assert Type.cast("dirty", []) == :error
      assert Type.cast("$", []) == :error
      assert Type.cast("ABC1000DEF", []) == {:ok, %Money{amount: 100_000, currency: :USD}}
      assert Type.cast("10,20.30,40.50", []) == {:ok, %Money{amount: 102_030, currency: :USD}}
    end

    test "load int" do
      assert Type.load(100_000_000, nil, []) == {:ok, %Money{amount: 100_000_000, currency: :USD}}
    end

    test "load int with opts" do
      opts = [currency: :EUR, opts: [separator: ".", delimiter: ","]]
      assert Type.load(100_000_000, nil, opts) == {:ok, %Money{amount: 100_000_000, currency: :EUR}}
    end

    test "load binary" do
      assert Type.load("100000000", nil, []) == :error
    end

    test "load nil" do
      assert Type.load(nil, nil, []) == :error
    end

    test "dump money" do
      assert Type.dump(%Money{amount: 1000}, nil, []) == {:ok, 1000}
    end

    test "dump int" do
      assert Type.dump(1000, nil, []) == {:ok, 1000}
    end

    test "dump binary" do
      assert Type.dump("1000", nil, []) == {:ok, nil}
    end

    test "dump nil" do
      assert Type.dump(nil, nil, []) == {:ok, nil}
    end
  end
end
