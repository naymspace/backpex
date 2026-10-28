defmodule Backpex.Test.ResourceActions.Email do
  @moduledoc """
  A resource action with a multi select field. It only shows a flash.
  """

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
      text: %{module: Backpex.Fields.Textarea, label: "Text", type: :string}
    ]
  end

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata) do
    change
    |> cast(attrs, [:users, :text])
    |> validate_required([:users, :text])
  end

  @impl Backpex.ResourceAction
  def handle(socket, _data) do
    {:ok, Phoenix.LiveView.put_flash(socket, :info, "An email has been successfully sent to the specified users.")}
  end
end
