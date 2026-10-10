defmodule Backpex.Fields.HasManyThroughTest do
  use Demo.DataCase, async: false

  import Demo.EctoFactory

  alias Backpex.Fields.HasManyThrough
  alias Demo.User
  alias Phoenix.LiveView.Socket

  setup do
    Enum.each(~w[Berlin Bern Munich], &insert(:address, city: &1))
  end

  describe "options depending on the form" do
    test "are loaded again when the options query changes" do
      socket = update_field(%Socket{}, form("Be"))

      assert option_labels(socket) == ~w[Berlin Bern]

      socket = update_field(socket, form("Mu"))

      assert option_labels(socket) == ~w[Munich]
    end

    test "are not loaded again while the options query stays the same" do
      socket = update_field(%Socket{}, form("Be"))

      assert count_address_queries(fn -> update_field(socket, form("Be", "Changed last name")) end) == 0
      assert count_address_queries(fn -> update_field(socket, form("Mu")) end) > 0
    end
  end

  defp field do
    {:addresses,
     %{
       module: HasManyThrough,
       label: "Addresses",
       display_field: :city,
       live_resource: DemoWeb.AddressLive,
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
      live_resource: DemoWeb.UserLive,
      form: form
    }

    {:ok, socket} = HasManyThrough.update(assigns, socket)
    socket
  end

  # The first option is the prompt.
  defp option_labels(socket), do: socket.assigns.options |> tl() |> Enum.map(fn {label, _id} -> label end)

  defp count_address_queries(fun) do
    ref = make_ref()
    handler_id = {__MODULE__, ref}
    :telemetry.attach(handler_id, [:demo, :repo, :query], &__MODULE__.handle_query/4, {self(), ref})

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    receive_address_queries(ref, 0)
  end

  @doc false
  def handle_query(_event, _measurements, %{source: "addresses"}, {test_pid, ref}) do
    if self() == test_pid, do: send(test_pid, {ref, :query})
  end

  def handle_query(_event, _measurements, _metadata, _config), do: :ok

  defp receive_address_queries(ref, count) do
    receive do
      {^ref, :query} -> receive_address_queries(ref, count + 1)
    after
      0 -> count
    end
  end
end
