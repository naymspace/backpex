defmodule Backpex.Filters.SelectTest do
  use ExUnit.Case, async: true

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Filters.Select, as: SelectFilter

  doctest SelectFilter

  defmodule TranslatingLive do
    @moduledoc false
    def translate({msg, _opts}), do: msg
  end

  describe "prompt/2" do
    test "returns the prompt option, the result of a prompt function or a default prompt" do
      assert SelectFilter.prompt({:status, %{prompt: "Any status"}}, %{}) == "Any status"
      assert SelectFilter.prompt({:status, %{prompt: fn assigns -> assigns.prompt end}}, %{prompt: "Pick"}) == "Pick"
      assert SelectFilter.prompt({:status, %{}}, %{live_resource: TranslatingLive}) == "Select an option..."
    end
  end

  describe "condition/3" do
    test "keeps the items whose field equals the value" do
      assert SelectFilter.condition({:status, %{}}, "open", %{}) == expr(status == "open")
      assert SelectFilter.condition({:priority, %{}}, 1, %{}) == expr(priority == 1)
    end
  end

  describe "changeset/3" do
    defp test_options do
      [{"Open", :open}, {"Closed", :closed}, {"Pending", "pending"}]
    end

    test "validates selected value exists in options (atom)" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "open"}, [:status])

      result = SelectFilter.changeset(changeset, {:status, %{options: test_options()}}, %{})

      assert result.valid?
    end

    test "validates selected value exists in options (string)" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "pending"}, [:status])

      result = SelectFilter.changeset(changeset, {:status, %{options: test_options()}}, %{})

      assert result.valid?
    end

    test "returns error for invalid option value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "invalid"}, [:status])

      result = SelectFilter.changeset(changeset, {:status, %{options: test_options()}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :status)
    end

    test "accepts nil value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{}, [:status])

      result = SelectFilter.changeset(changeset, {:status, %{options: test_options()}}, %{})

      assert result.valid?
    end

    test "accepts empty string value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: ""}, [:status])

      result = SelectFilter.changeset(changeset, {:status, %{options: test_options()}}, %{})

      assert result.valid?
    end
  end
end
