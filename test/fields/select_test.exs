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

  describe "render_form/1" do
    test "renders a combobox with the options and the value of the form" do
      document = render_form([Admin: "admin", User: "user"], "user")

      assert attribute(document, "#change_role", "phx-hook") == ["BackpexCombobox"]
      assert attribute(document, "#change_role", "data-multiple") == []
      assert attribute(document, "[role=option]", "data-value") == ["admin", "user"]
      assert texts(document, "[role=option][aria-selected=true]") == ["User"]
      assert texts(document, "[data-part=value-label]") == ["User"]
      assert anchor_value(document) == ["user"]
    end

    test "renders grouped options in their groups" do
      options = [{"Europe", [Germany: "de", Austria: "at"]}, {"North America", [USA: "us"]}]
      document = render_form(options, "at")

      assert texts(document, "[data-part=group-label]") == ["Europe", "North America"]
      assert texts(document, "[role=option][aria-selected=true]") == ["Austria"]
    end

    test "is named by its label, which opens the combobox" do
      document = render_form([A: "a"], "a")

      assert texts(document, "label#change_role-label[for=change_role-trigger]") == ["Role"]

      assert attribute(document, "#change_role-trigger", "aria-labelledby") ==
               ["change_role-label change_role-value"]
    end

    test "shows the prompt and a clear button, and selects no option without a value" do
      document = render_form([A: "a", B: "b"], nil, prompt: "Choose a role")

      assert texts(document, "[data-part=placeholder]:not([hidden])") == ["Choose a role"]
      assert document |> LazyHTML.query("[data-part=clear]") |> Enum.count() == 1
      assert texts(document, "[role=option][aria-selected=true]") == []
      assert anchor_value(document) == [""]
    end

    test "takes the prompt from a function that receives the assigns" do
      document = render_form([A: "a"], nil, prompt: fn assigns -> "Choose a #{assigns.name}" end)

      assert texts(document, "[data-part=placeholder]") == ["Choose a role"]
    end

    test "selects its first option without a prompt and a value, like a native select" do
      for value <- [nil, ""] do
        document = render_form([{"Europe", [Germany: "de"]}, {"USA", "us"}], value)

        assert document |> LazyHTML.query("[data-part=clear]") |> Enum.empty?()
        assert texts(document, "[role=option][aria-selected=true]") == ["Germany"]
        assert anchor_value(document) == ["de"]
      end
    end

    test "keeps the value of the form without a prompt" do
      assert [A: "a", B: "b"] |> render_form("b") |> anchor_value() == ["b"]
    end

    test "has a search input only with searchable_options" do
      refute [A: "a"] |> render_form("a") |> search_input?()
      refute [A: "a"] |> render_form("a", searchable_options: false) |> search_input?()
      assert [A: "a"] |> render_form("a", searchable_options: true) |> search_input?()
    end

    test "a readonly field shows the value without a popup" do
      document = render_form([A: "a"], "a", [prompt: "Choose"], readonly: true)

      assert texts(document, "[data-part=value-label]") == ["A"]
      assert attribute(document, "#change_role-trigger", "aria-readonly") == ["true"]
      assert document |> LazyHTML.query("[role=listbox], [data-part=clear]") |> Enum.empty?()
    end
  end

  describe "render_index_form/1" do
    test "renders a small combobox that is named by the label of the field" do
      document = render_index_form([A: "a", B: "b"], "b")

      assert attribute(document, "#index-form-input-role-1", "phx-hook") ==
               ["BackpexCombobox"]

      assert attribute(document, "#index-form-input-role-1-trigger", "aria-label") == ["Role"]
      assert attribute(document, "input[data-part=anchor]", "name") == ["index_form[value]"]
      assert anchor_value(document) == ["b"]

      [class] = attribute(document, "[data-part=control]", "class")
      assert "input-sm" in String.split(class)
      assert "not-hover:input-ghost" in String.split(class)
    end

    test "has a search input only with searchable_options" do
      refute [A: "a"] |> render_index_form("a") |> search_input?()
      assert [A: "a"] |> render_index_form("a", searchable_options: true) |> search_input?()
    end

    test "a readonly field is disabled" do
      document = render_index_form([A: "a"], "a", [], readonly: true)

      assert attribute(document, "input[data-part=anchor]", "disabled") == [""]
      assert document |> LazyHTML.query("[role=listbox]") |> Enum.empty?()
    end
  end

  defmodule ItemLive do
    @moduledoc false
    def config(:primary_key), do: :id
    def translate({msg, _opts}), do: msg
  end

  defp render_form(options, value, field_options \\ [], assigns \\ []) do
    assigns =
      Keyword.merge(
        [
          name: :role,
          field_options: Map.merge(%{module: Select, label: "Role", options: options}, Map.new(field_options)),
          form: Phoenix.Component.to_form(%{"role" => value}, as: :change),
          live_resource: nil,
          readonly: false,
          hide_label: false
        ],
        assigns
      )

    (&Select.render_form/1) |> render_component(assigns) |> LazyHTML.from_fragment()
  end

  defp render_index_form(options, value, field_options \\ [], assigns \\ []) do
    assigns =
      Keyword.merge(
        [
          name: :role,
          field_options: Map.merge(%{module: Select, label: "Role", options: options}, Map.new(field_options)),
          item: %{id: 1},
          value: value,
          live_resource: ItemLive,
          readonly: false
        ],
        assigns
      )

    (&Select.render_index_form/1) |> render_component(assigns) |> LazyHTML.from_fragment()
  end

  defp attribute(document, selector, name), do: document |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp texts(document, selector) do
    document |> LazyHTML.query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp anchor_value(document), do: document |> LazyHTML.query("input[data-part=anchor]") |> LazyHTML.attribute("value")

  defp search_input?(document), do: document |> LazyHTML.query("input[data-part=search]") |> Enum.any?()

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
