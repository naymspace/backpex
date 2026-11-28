defmodule Backpex.Fields.MultiSelectTest do
  use ExUnit.Case, async: true

  alias Backpex.Fields.MultiSelect

  defmodule UserLive do
    @moduledoc false
    def translate({msg, _opts}), do: msg
  end

  @options [{"Alex", "alex"}, {"Bob", "bob"}, {"Carol", "carol"}]

  @grouped_options [
    {"Admins", [{"Alex", "alex"}, {"Bob", "bob"}]},
    {"Editors", [{"Carol", "carol"}, {"Dave", "dave"}]}
  ]

  defp mount(options, selected, assigns \\ %{}, field_options \\ %{}) do
    assigns =
      Map.merge(
        %{
          field_options: Map.merge(%{module: MultiSelect, label: "Users", options: options}, field_options),
          form: Phoenix.Component.to_form(%{"users" => selected}, as: :change),
          hide_label: false,
          item: %{},
          live_resource: UserLive,
          name: :users,
          readonly: false,
          type: :form
        },
        assigns
      )

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, myself: %Phoenix.LiveComponent.CID{cid: 1}}}

    {:ok, socket} = MultiSelect.update(assigns, socket)
    socket
  end

  defp render(socket) do
    socket.assigns
    |> MultiSelect.render_form()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  defp attribute(document, selector, name), do: document |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp texts(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp option_labels(document), do: texts(document, "[role=option]")

  # Serialize the form controls the browser would submit, in DOM order.
  defp submitted_users(document) do
    document
    |> LazyHTML.query("input[name]:not([disabled])")
    |> Enum.map(fn input ->
      [name] = LazyHTML.attribute(input, "name")
      [value] = LazyHTML.attribute(input, "value")
      {name, value}
    end)
    |> URI.encode_query()
    |> Plug.Conn.Query.decode()
    |> get_in(["change", "users"])
  end

  describe "render_form/1" do
    test "renders a combobox for multiple values with a search input" do
      document = mount(@options, []) |> render()

      assert attribute(document, "#change_users", "phx-hook") == ["BackpexCombobox"]
      assert attribute(document, "#change_users", "data-multiple") == [""]
      assert attribute(document, "[role=listbox]", "aria-multiselectable") == ["true"]
      assert document |> LazyHTML.query("#change_users-search") |> Enum.count() == 1
      assert option_labels(document) == ["Alex", "Bob", "Carol"]
    end

    test "renders the options of each group in the group" do
      document = mount(@grouped_options, []) |> render()

      assert texts(document, "[data-part=group-label]") == ["Admins", "Editors"]
      assert texts(document, "[role=group]:first-child [role=option]") == ["Alex", "Bob"]
      assert option_labels(document) == ["Alex", "Bob", "Carol", "Dave"]
    end

    test "marks the selected options and submits their values" do
      document = mount(@options, ["alex", "carol"]) |> render()

      assert texts(document, "[role=option][aria-selected=true]") == ["Alex", "Carol"]
      assert texts(document, "[data-part=badge-label]") == ["Alex", "Carol"]
      assert submitted_users(document) == ["alex", "carol"]
    end

    test "submits an empty value when no option is selected" do
      assert mount(@options, []) |> render() |> submitted_users() == ""
    end

    test "sends no event to the server for a selection" do
      document = mount(@options, ["alex"]) |> render()

      # The combobox changes its inputs in the browser, the form's `phx-change` submits them.
      assert document |> LazyHTML.query("[role=option][phx-click], [data-part=badge] [phx-click]") |> Enum.empty?()
    end

    test "names the combobox by the label of the field" do
      document = mount(@options, []) |> render()

      assert texts(document, "label#change_users-label[for=change_users-trigger]") == ["Users"]
      assert attribute(document, "[role=listbox]", "aria-labelledby") == ["change_users-label"]

      assert attribute(document, "#change_users-trigger", "aria-labelledby") ==
               ["change_users-label change_users-value"]
    end

    test "names the combobox by the given ids or the label text when the label is hidden" do
      document = mount(@options, [], %{hide_label: true, aria_labelledby: "row column"}) |> render()

      assert document |> LazyHTML.query("label[for]") |> Enum.empty?()
      assert attribute(document, "[role=listbox]", "aria-labelledby") == ["row column"]

      document = mount(@options, [], %{hide_label: true}) |> render()

      assert attribute(document, "[role=listbox]", "aria-label") == ["Users"]
    end

    test "a readonly field shows the selection without a popup and still submits it" do
      document = mount(@options, ["bob"], %{readonly: true}) |> render()

      assert texts(document, "[data-part=badge-label]") == ["Bob"]
      assert attribute(document, "#change_users-trigger", "aria-readonly") == ["true"]
      assert attribute(document, "#change_users", "phx-hook") == []
      assert document |> LazyHTML.query("[role=listbox], [data-part=badge-remove]") |> Enum.empty?()
      assert submitted_users(document) == ["bob"]
    end
  end

  describe "select all" do
    test "is offered by the combobox, which selects and deselects in the browser" do
      document = mount(@grouped_options, ["alex"]) |> render()

      assert texts(document, "[data-part=select-all] button") == ["Select all", "Deselect all"]
      assert texts(document, "[data-part=selected-count]") == ["1"]
      assert document |> LazyHTML.query("[data-part=select-all] [phx-click]") |> Enum.empty?()
    end

    test "is not offered by a readonly field" do
      document = mount(@options, ["alex"], %{readonly: true}) |> render()

      assert document |> LazyHTML.query("[data-part=select-all]") |> Enum.empty?()
    end
  end

  describe "prompt" do
    test "is shown while no option is selected" do
      document = mount(@options, [], %{}, %{prompt: "Pick users"}) |> render()

      assert texts(document, "[data-part=placeholder]:not([hidden])") == ["Pick users"]
      refute LazyHTML.text(document) =~ "Select options..."
    end

    test "is hidden while an option is selected" do
      document = mount(@options, ["alex"], %{}, %{prompt: "Pick users"}) |> render()

      assert texts(document, "[data-part=placeholder][hidden]") == ["Pick users"]
    end

    test "can be a function that receives the assigns" do
      prompt = fn assigns -> "Pick #{String.downcase(assigns.field_options.label)}" end
      document = mount(@options, [], %{}, %{prompt: prompt}) |> render()

      assert texts(document, "[data-part=placeholder]") == ["Pick users"]
    end

    test "defaults to Backpex's text" do
      assert mount(@options, []) |> render() |> texts("[data-part=placeholder]") == ["Select options..."]
    end
  end

  describe "not_found_text" do
    test "is the text the combobox shows when no option matches the search" do
      document = mount(@options, [], %{}, %{not_found_text: "Nobody here"}) |> render()

      # Hidden while there are options; the hook shows it when the search matches none.
      assert texts(document, "[data-part=empty][hidden]") == ["Nobody here"]
      refute LazyHTML.text(document) =~ "No options found"
    end

    test "defaults to Backpex's text" do
      assert mount(@options, []) |> render() |> texts("[data-part=empty]") == ["No options found"]
    end
  end

  describe "selection" do
    # The values come from the form params, which the client controls.
    test "ignores a submitted value that matches no option" do
      socket = mount(@options, ["alex", "nobody"])

      assert socket.assigns.selected == [{"Alex", "alex"}]
      assert socket |> render() |> submitted_users() == ["alex"]
    end
  end
end
