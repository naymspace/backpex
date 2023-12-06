defmodule Backpex.Ecto.Amount.Type do
  @moduledoc """
  Provides a type for Ecto to store a amount.
  The underlying data type should be an integer.
  ## Migration

      create table(:my_table) do
        add :amount, :integer
      end

  ## Schema

      schema "my_table" do
        field :amount, Backpex.Ecto.Amount.Type
      end

      schema "my_table" do
        field :amount, Backpex.Ecto.Amount.Type, currency: :EUR, separator: ".", delimiter: ","
      end
  """

  use Ecto.ParameterizedType

  def type(_params), do: :integer

  def init(opts), do: opts

  def cast(str, opts) when is_binary(str) do
    currency = Keyword.get(opts, :currency, :USD)

    Money.parse(str, currency, opts)
  end

  def cast(int, opts) when is_integer(int) do
    currency = Keyword.get(opts, :currency, :USD)

    {:ok, Money.new(int, currency)}
  end

  def cast(nil, opts) do
    currency = Keyword.get(opts, :currency, :USD)

    {:ok, Money.new(0, currency)}
  end

  def cast(%Money{} = money, _opts), do: {:ok, money}

  def cast(_val, _opts), do: :error

  def load(int, _loader, opts) when is_integer(int) do
    currency = Keyword.get(opts, :currency, :USD)

    {:ok, Money.new(int, currency)}
  end

  def load(_val, _loader, _opts), do: :error

  def dump(int, _dumper, _opts) when is_integer(int), do: {:ok, int}
  def dump(%Money{} = m, _dumper, _opts), do: {:ok, m.amount}
  def dump(_val, _dumper, _opts), do: {:ok, nil}
end
