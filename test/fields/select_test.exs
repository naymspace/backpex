defmodule Backpex.Fields.SelectTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.Select

  describe "render_value/1" do
    test "renders the label of a flat option" do
      assert render_label([Admin: "admin", User: "user"], "user") == "User"
      assert render_label([{"Admin", "admin"}, {"User", "user"}], "admin") == "Admin"
    end

    test "renders plain values as their own label" do
      assert render_label(["admin", "user"], "user") == "user"
    end

    test "renders the label of an option in a list group" do
      options = [{"Europe", [Germany: "de", Austria: "at"]}, {"North America", [USA: "us"]}]

      assert render_label(options, "at") == "Austria"
    end

    test "renders the label of an option in a map group" do
      options = [{"Group", %{"A" => "a", "B" => "b"}}]

      assert render_label(options, "b") == "B"
    end

    test "renders the label of an option in a top-level map" do
      options = %{"Europe" => [Germany: "de"], "North America" => %{"USA" => "us", "Canada" => "ca"}}

      assert render_label(options, "de") == "Germany"
      assert render_label(options, "ca") == "Canada"
    end

    test "renders the label of a keyword list option" do
      options = [[key: "Admin", value: "admin"], [key: "User", value: "user", disabled: true]]

      assert render_label(options, "user") == "User"
      assert render_label([{"Roles", options}], "admin") == "Admin"
    end

    test "treats struct values as plain values" do
      assert render_label([{"New Year", ~D[2026-01-01]}], "2026-01-01") == "New Year"
    end

    test "ignores separators" do
      assert render_label([:hr, {:hr, nil}, Admin: "admin"], "admin") == "Admin"
    end

    test "renders the value when no option matches" do
      assert render_label([{"Group", %{"A" => "a"}}], "zzz") == "zzz"
    end

    test "renders a placeholder when the value is nil" do
      assert render_label([{"Group", %{"A" => "a"}}], nil) == "—"
    end

    test "renders the label of an option in a nested group" do
      options = [{"Outer", [{"Inner", %{"A" => "a"}}, {"Other", [B: "b"]}]}]

      assert render_label(options, "a") == "A"
      assert render_label(options, "b") == "B"
    end

    test "skips empty groups" do
      assert render_label([{"Empty", []}, {"Also empty", %{}}, B: "b"], "b") == "B"
    end

    test "handles plain values and separators inside groups" do
      assert render_label(%{"Group" => ["plain", :hr, {"A", "a"}]}, "plain") == "plain"
      assert render_label(%{"Group" => ["plain", :hr, {"A", "a"}]}, "a") == "A"
      assert render_label([{"Group", %{:hr => nil, "A" => "a"}}], "a") == "A"
    end

    test "compares integer and atom option values with the stored value" do
      assert render_label([{"A", 1}], "1") == "A"
      assert render_label([{"A", 1}], 1) == "A"
      assert render_label([{"A", :a}], "a") == "A"
      assert render_label([{"A", :a}], :a) == "A"
    end

    test "renders the label of a nil or empty option when the value is nil" do
      assert render_label([{"None", nil}, A: "a"], nil) == "None"
      assert render_label([{"Empty", ""}, A: "a"], nil) == "Empty"
    end
  end

  defp render_label(options, value) do
    Select
    |> Function.capture(:render_value, 1)
    |> render_component(
      value: value,
      live_action: :show,
      field_options: %{module: Select, label: "Field", options: options}
    )
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
  end
end
