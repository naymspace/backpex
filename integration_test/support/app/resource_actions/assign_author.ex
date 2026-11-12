defmodule Backpex.Test.ResourceActions.AssignAuthor do
  @moduledoc """
  A resource action of posts with a BelongsTo field. Its `options_query` reads another value of the form and has a
  `limit`: it only offers the oldest user with the first name of the form. The item of the action is a plain map, as
  with the default `base_schema/1`. It only shows a flash.
  """

  use Backpex.ResourceAction

  import Ecto.Changeset
  import Ecto.Query

  @impl Backpex.ResourceAction
  def title, do: "Assign author"

  @impl Backpex.ResourceAction
  def label, do: "Assign author"

  @impl Backpex.ResourceAction
  def fields do
    [
      first_name: %{module: Backpex.Fields.Text, label: "First name"},
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :username,
        options_query: fn query, assigns ->
          first_name = assigns.form[:first_name].value || ""

          query
          |> where([user], user.first_name == ^first_name)
          |> order_by([user], asc: user.id)
          |> limit(1)
        end
      }
    ]
  end

  # The BelongsTo field submits its owner key, which the default types of the fields don't contain.
  @impl Backpex.ResourceAction
  def base_schema(_assigns), do: {%{}, %{first_name: :string, user_id: :integer}}

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata) do
    change
    |> cast(attrs, [:first_name, :user_id])
    |> validate_required([:first_name, :user_id])
  end

  @impl Backpex.ResourceAction
  def handle(socket, _data) do
    {:ok, Phoenix.LiveView.put_flash(socket, :info, "The author has been assigned.")}
  end
end
