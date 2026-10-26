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
