defmodule Backpex.Integration.Fields.HasManyThroughTest do
  use Backpex.ConnCase, async: true

  import Ecto.Query

  alias Backpex.Fields.HasManyThrough
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
  defp option_labels(socket), do: socket.assigns.options |> tl() |> Enum.map(fn {label, _id} -> label end)
end
