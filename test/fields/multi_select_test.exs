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

  defp mount(options, selected) do
    assigns = %{
      field_options: %{module: MultiSelect, label: "Users", options: options},
      form: Phoenix.Component.to_form(%{"users" => selected}, as: :change),
      hide_label: false,
      item: %{},
      live_resource: UserLive,
      name: :users,
      readonly: false,
      type: :form
    }

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, myself: %Phoenix.LiveComponent.CID{cid: 1}}}

    {:ok, socket} = MultiSelect.update(assigns, socket)
    socket
  end

  defp search(socket, search_input) do
    {:noreply, socket} = MultiSelect.handle_event("search", %{"change[users]_search" => search_input}, socket)
    socket
  end

  defp rendered_labels(socket) do
    socket
    |> render()
    |> LazyHTML.query("label span")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  # Serialize the form controls the browser would submit, in DOM order.
  defp submitted_users(socket) do
    socket
    |> render()
    |> LazyHTML.query("input[name]:not([type=checkbox]), input[name][type=checkbox][checked]")
    |> Enum.map(fn input ->
      [name] = LazyHTML.attribute(input, "name")
      [value] = LazyHTML.attribute(input, "value")
      {name, value}
    end)
    |> URI.encode_query()
    |> Plug.Conn.Query.decode()
    |> get_in(["change", "users"])
  end

  defp render(socket) do
    socket.assigns
    |> MultiSelect.render_form()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> LazyHTML.from_fragment()
  end

  describe "search" do
    test "filters flat options by label" do
      socket = mount(@options, []) |> search("aL")

      assert rendered_labels(socket) == ["Alex"]
    end

    test "filters grouped options by the label of each option" do
      socket = mount(@grouped_options, []) |> search("car")

      assert rendered_labels(socket) == ["Carol"]
      assert render(socket) |> LazyHTML.text() =~ "Editors"
      refute render(socket) |> LazyHTML.text() =~ "Admins"
    end

    test "does not match options by their group label" do
      socket = mount(@grouped_options, []) |> search("admins")

      assert rendered_labels(socket) == []
      assert render(socket) |> LazyHTML.text() =~ "No options found"
    end

    test "shows all options for a blank search" do
      for search_input <- ["", "  "] do
        socket = mount(@grouped_options, []) |> search(search_input)

        assert rendered_labels(socket) == ["Alex", "Bob", "Carol", "Dave"]
      end
    end

    test "shows the not found text when no option matches" do
      socket = mount(@options, []) |> search("zzz")

      assert rendered_labels(socket) == []
      assert render(socket) |> LazyHTML.text() =~ "No options found"
    end

    test "keeps selected options that are hidden by the search in the form params" do
      socket = mount(@options, ["alex", "carol"]) |> search("bob")

      assert rendered_labels(socket) == ["Bob"]
      assert submitted_users(socket) |> Enum.sort() == ["alex", "carol"]
    end
  end

  describe "after a search" do
    test "select all selects all options" do
      socket = mount(@grouped_options, []) |> search("car")

      {:noreply, socket} = MultiSelect.handle_event("toggle-select-all", %{}, socket)

      assert socket.assigns.selected == [{"Alex", "alex"}, {"Bob", "bob"}, {"Carol", "carol"}, {"Dave", "dave"}]
      assert submitted_users(socket) |> Enum.sort() == ["alex", "bob", "carol", "dave"]

      {:noreply, socket} = MultiSelect.handle_event("toggle-select-all", %{}, socket)

      assert socket.assigns.selected == []
      assert submitted_users(socket) == ""
    end

    test "removing the badge of a hidden option unselects it" do
      socket = mount(@options, ["alex", "carol"]) |> search("bob")

      {:noreply, socket} = MultiSelect.handle_event("toggle-option", %{"id" => "alex"}, socket)

      assert socket.assigns.selected == [{"Carol", "carol"}]
      assert socket.assigns.show_select_all
      assert submitted_users(socket) == ["carol"]
    end
  end
end
