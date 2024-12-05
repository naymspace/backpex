defmodule DemoWeb.ResourceActions.Email do
  @moduledoc false

  use Backpex.ResourceAction

  import Ecto.Changeset

  @impl Backpex.ResourceAction
  def title, do: "Send email"
  @impl Backpex.ResourceAction
  def label, do: "Send email"

  @impl Backpex.ResourceAction
  def fields do
    [
      users: %{
        module: Backpex.Fields.MultiSelect,
        label: "Users",
        options: fn _assigns -> [{"Alex", "user_id_alex"}, {"Bob", "user_id_bob"}] end,
        type: {:array, :string}
      },
      text: %{
        module: Backpex.Fields.Textarea,
        label: "Text",
        type: :string
      }
    ]
  end

  @required_fields ~w[text users]a

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata \\ []) do
    change
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  @impl Backpex.ResourceAction
  def handle(socket, _data) do
    # Send mail

    # We suppose there was no error.
    socket = Phoenix.LiveView.put_flash(socket, :info, "An email has been successfully sent to the specified users.")

    {:ok, socket}
  end
end
