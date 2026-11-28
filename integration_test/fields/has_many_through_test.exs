defmodule Backpex.Integration.Fields.HasManyThroughTest do
  use Backpex.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest, only: [element: 2, element: 3, render_click: 1, render_hook: 3]

  alias Backpex.Fields.HasManyThrough
  alias Backpex.Test.Repo
  alias Backpex.Test.User
  alias Backpex.Test.UsersAddresses
  alias Phoenix.LiveView.Socket

  describe "options depending on the form" do
    setup do
      Enum.each(~w[Berlin Bern Munich], &insert(:address, city: &1))
    end

    test "are loaded again when the options query changes" do
      socket = update_field(%Socket{}, form("Be"))

      assert option_labels(socket) == ~w[Berlin Bern]

      socket = update_field(socket, form("Mu"))

      assert option_labels(socket) == ~w[Munich]
    end

    test "are not loaded again while the options query stays the same" do
      socket = update_field(%Socket{}, form("Be"))

      assert count_queries("addresses", fn -> update_field(socket, form("Be", "Changed last name")) end) == 0
      assert count_queries("addresses", fn -> update_field(socket, form("Mu")) end) > 0
    end
  end

  describe "pivot fields" do
    setup do
      %{user: insert(:user, users_addresses: [%UsersAddresses{address: build(:address), type: :billing}])}
    end

    test "are rendered on the edit view", %{conn: conn, user: user} do
      conn
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> assert_has("form#resource-form")
      |> assert_has("td", text: "Billing")
    end

    test "are rendered on the show view", %{conn: conn, user: user} do
      conn
      |> visit(~p"/admin/users/#{user.id}/show")
      |> assert_has("h1", text: "User", exact: true)
      |> assert_has("td", text: "Billing")
    end
  end

  describe "an existing relation" do
    setup do
      %{user: insert(:user, users_addresses: [%UsersAddresses{address: build(:address), type: :billing}])}
    end

    test "keeps its pivot record when the form is saved", %{conn: conn, user: user} do
      [%UsersAddresses{id: pivot_id}] = user.users_addresses

      conn
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> fill_in("First Name", with: "Changed")
      |> click_button("Save")
      |> assert_path(~p"/admin/users")

      assert [%UsersAddresses{id: ^pivot_id, type: :billing}] = Repo.all(UsersAddresses)
    end
  end

  # The addresses of `Backpex.Test.UserRelationOptionsLive` have an `options_query` that only offers German addresses.
  describe "options_query on save" do
    setup do
      %{german: insert(:address, country: :de), american: insert(:address, country: :us)}
    end

    test "refuses to link a child that is not an option", %{conn: conn, american: american} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> save(%{users_addresses: %{"0" => %{address_id: american.id, type: "billing"}}})
      # The error belongs to the field, not to one of its rows, so the field shows it.
      |> assert_has("#resource-form p.text-error", text: "is invalid", exact: true)

      assert linked_addresses(user) == []
    end

    test "links a child that is an option", %{conn: conn, german: german} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> save(%{users_addresses: %{"0" => %{address_id: german.id, type: "billing"}}})

      assert linked_addresses(user) == [german.id]
    end

    test "refuses a child that is not an option through the entries of the add and remove buttons", %{
      conn: conn,
      american: american
    } do
      user = insert(:user)

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> unwrap(fn view ->
        form_component = Phoenix.LiveViewTest.with_target(view, "#form-component")
        entry = %{"0" => %{"address_id" => american.id, "type" => "billing"}}

        Phoenix.LiveViewTest.render_change(form_component, "validate", %{
          "change" => %{"users_addresses" => entry},
          "_target" => ["change", "users_addresses"]
        })

        # Both buttons put the entries of the validated changeset into the assocs of the form.
        view
        |> Phoenix.LiveViewTest.element("button[phx-click='new-relational']")
        |> Phoenix.LiveViewTest.render_click()

        view
        |> Phoenix.LiveViewTest.element("button[phx-click='detach-relational'][phx-value-index='1']")
        |> Phoenix.LiveViewTest.render_click()

        Phoenix.LiveViewTest.render_submit(form_component, "save", %{
          "change" => %{"username" => "after"},
          "save-type" => "save"
        })
      end)

      assert linked_addresses(user) == []
    end

    # The assocs of the form can be older than the params, which replace them in the changeset.
    test "ignores the entries of the add and remove buttons when the params have entries", %{
      conn: conn,
      german: german,
      american: american
    } do
      user = insert(:user)

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> unwrap(fn view ->
        form_component = Phoenix.LiveViewTest.with_target(view, "#form-component")

        Phoenix.LiveViewTest.render_change(form_component, "validate", %{
          "change" => %{"users_addresses" => %{"0" => %{"address_id" => american.id, "type" => "billing"}}},
          "_target" => ["change", "users_addresses"]
        })

        view
        |> Phoenix.LiveViewTest.element("button[phx-click='new-relational']")
        |> Phoenix.LiveViewTest.render_click()

        Phoenix.LiveViewTest.render_submit(form_component, "save", %{
          "change" => %{"users_addresses" => %{"0" => %{"address_id" => german.id, "type" => "billing"}}},
          "save-type" => "save"
        })
      end)

      assert linked_addresses(user) == [german.id]
    end

    # After a click on the add button, a linked child is in the params and in the assocs of the form.
    test "links an option next to a linked child that is not an option after a click on the add button", %{
      conn: conn,
      german: german,
      american: american
    } do
      user = insert(:user, users_addresses: [%UsersAddresses{address_id: american.id, type: :billing}])
      [link] = user.users_addresses

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> unwrap(fn view ->
        view
        |> Phoenix.LiveViewTest.element("button[phx-click='new-relational']")
        |> Phoenix.LiveViewTest.render_click()

        view
        |> Phoenix.LiveViewTest.with_target("#form-component")
        |> Phoenix.LiveViewTest.render_submit("save", %{
          "change" => %{
            "users_addresses" => %{
              "0" => %{"id" => link.id, "address_id" => american.id, "type" => "billing"},
              "1" => %{"address_id" => german.id, "type" => "billing"}
            }
          },
          "save-type" => "save"
        })
      end)

      assert user |> linked_addresses() |> Enum.sort() == Enum.sort([american.id, german.id])
    end

    test "keeps a linked child that is not an option", %{conn: conn, american: american} do
      user = insert(:user, users_addresses: [%UsersAddresses{address_id: american.id, type: :billing}])
      [link] = user.users_addresses

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> save(%{username: "after", users_addresses: %{"0" => %{id: link.id, address_id: american.id, type: "billing"}}})

      assert %User{username: "after"} = Repo.get!(User, user.id)
      assert linked_addresses(user) == [american.id]
    end
  end

  # The addresses of `Backpex.Test.UserRelationOptionsLive` load 2 options at a time and are searched on the server by
  # their street, by which the options query orders them.
  describe "server search" do
    @combobox "#resource-form_users_addresses_0_address_id"

    setup do
      addresses = for street <- ["Elm Street", "Oak Street", "Pine Street"], do: insert(:address, street: street)
      insert(:address, street: "Oak Avenue", country: :us)

      %{addresses: addresses}
    end

    test "loads a page of options, loads more and searches them", %{conn: conn, addresses: addresses} do
      [first, second, third] = addresses

      conn
      |> visit(~p"/admin/user-relation-options/#{insert(:user).id}/edit")
      |> click_button("Attach Address")
      |> assert_has("#{@combobox} [role=option]", count: 2)
      |> assert_has("#{@combobox} [role=option][data-value='#{first.id}']", text: first.street, exact: true)
      |> assert_has("#{@combobox} [role=option][data-value='#{second.id}']", text: second.street, exact: true)
      |> assert_has("#{@combobox}[data-on-search=search]")
      |> unwrap(&(&1 |> element("#{@combobox}-popup button", "Show more") |> render_click()))
      |> assert_has("#{@combobox} [role=option]", count: 3)
      |> assert_has("#{@combobox} [role=option][data-value='#{third.id}']", text: third.street, exact: true)
      |> refute_has("#{@combobox}-popup button", text: "Show more")
      # The options query only offers German addresses, also to the search.
      |> search(@combobox, "oak")
      |> assert_has("#{@combobox} [role=option]", count: 1)
      |> assert_has("#{@combobox} [role=option]", text: "Oak Street", exact: true)
    end

    test "shows the linked address that is on no loaded page", %{conn: conn, addresses: [_first, _second, third]} do
      user = insert(:user, users_addresses: [%UsersAddresses{address_id: third.id, type: :billing}])

      conn
      |> visit(~p"/admin/user-relation-options/#{user.id}/edit")
      |> assert_has("td", text: third.street)
      |> assert_has("#{@combobox} [role=option]", count: 2)
      |> refute_has("#{@combobox} [role=option][data-value='#{third.id}']")
      |> assert_has("#{@combobox} [data-part=value-label]", text: third.street, exact: true)
    end
  end

  # The combobox pushes the text of its search input to the field.
  defp search(session, combobox, query) do
    unwrap(session, &(&1 |> element(combobox) |> render_hook("search", %{"query" => query})))
  end

  # A crafted client can send any value, not only the options of the select.
  defp save(session, params) do
    unwrap(session, fn view ->
      view
      |> Phoenix.LiveViewTest.form("#resource-form")
      |> Phoenix.LiveViewTest.put_submitter("button[value=save]")
      |> Phoenix.LiveViewTest.render_submit(%{change: params})
    end)
  end

  defp linked_addresses(user) do
    user
    |> Repo.preload(:users_addresses, force: true)
    |> Map.fetch!(:users_addresses)
    |> Enum.map(& &1.address_id)
  end

  defp field do
    {:addresses,
     %{
       module: HasManyThrough,
       label: "Addresses",
       display_field: :city,
       live_resource: Backpex.Test.AddressLive,
       options_query: fn query, assigns ->
         prefix = Phoenix.HTML.Form.input_value(assigns.form, :first_name) || ""

         query
         |> where([address], like(address.city, ^"#{prefix}%"))
         |> order_by([address], address.city)
       end
     }}
  end

  defp form(first_name, last_name \\ "Doe") do
    %User{users_addresses: []}
    |> Ecto.Changeset.cast(%{"first_name" => first_name, "last_name" => last_name}, [:first_name, :last_name])
    |> Phoenix.Component.to_form(as: :change)
  end

  defp update_field(socket, form) do
    {_name, field_options} = field = field()

    assigns = %{
      type: :form,
      name: :addresses,
      field: field,
      field_options: field_options,
      live_resource: Backpex.Test.UserLive,
      form: form
    }

    {:ok, socket} = HasManyThrough.update(assigns, socket)
    socket
  end

  # The first option is the prompt.
  defp option_labels(socket), do: Enum.map(socket.assigns.options, fn {label, _id} -> label end)
end
