defmodule Backpex.ItemAction do
  @moduledoc ~S'''
  Behaviour implemented by all item actions.

  An Item Action defines an action (such as deleting a user) that can be performed on one or more items.
  Unlike resource actions, item actions are not automatically performed on all items in a resource.
  First, items must be selected.

  There are multiple ways to perform an Item Action:
  - use the checkboxes in the first column of the resource table to select 1-n items and trigger the action later on
  - use an icon in the last column of the resource table to perform the Item Action for one item
  - use the corresponding icon in the show view to perform the Item Action for the corresponding item

  If you use the first method, you must trigger the item action using the button above the resource action. If you use the second or third method, the item action is triggered immediately.

  Therefore, you need to provide a label and an icon in your code. The label is displayed above the resource table and the icon
  is displayed for each element in the table and in the show view. This gives the user multiple ways to trigger your item action.

  Optionally, there can be a confirmation modal. You can enable this by specifying a text to be displayed in the modal via the `confirm` function. You can also specify a changeset and a list of fields. The fields are displayed in the confirm modal as well.
  For example, a field could be a reason for deleting a user.

  In the list of fields, each field needs a type. This is because we cannot infer a type from a schema.

  To add an item action to your resource you can use the `item_actions` function. This must be a keyword list.
  The keyword defines the name of the action. In addition, each keyword must define a map as a value. This map must at least
  provide the module for the item action with the `module` key. The "default" Item Actions (Delete, Edit and Show) are passed as
  parameters to the item_actions and may be appended to your item actions.

  Furthermore, you can specify which ways of triggering the item action are enabled with the `only` key.

  The only key must provide a list and accepts the following options
  - `:row` - display an icon for each element in the table that can trigger the Item Action for the corresponding element
  - `:index` - display a button at the top of the resource table, which triggers the Item Action for selected items
  - `:show` - display an icon in the show view that triggers the Item Action for the corresponding item

  The following example shows how to define a soft delete item action and replace it with the default delete Item Action.

  ## Example

      defmodule DemoWeb.ItemAction.SoftDelete do
        use BackpexWeb, :item_action

        alias Backpex.Resource

        @impl Backpex.ItemAction
        def icon(assigns) do
          ~H"""
          <Heroicons.eye class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-green-600" />
          """
        end

        @impl Backpex.ItemAction
        def fields do
          [
            reason: %{
              module: Backpex.Fields.Textarea,
              label: "Reason",
              type: :string
            }
          ]
        end

        @required_fields ~w[reason]a

        @impl Backpex.ItemAction
        def changeset(change, attrs) do
          change
          |> cast(attrs, @required_fields)
          |> validate_required(@required_fields)
        end

        @impl Backpex.ItemAction
        def label(_assigns), do: Backpex.translate("Delete")

        @impl Backpex.ItemAction
        def confirm_label(_assigns), do: Backpex.translate("Delete")

        @impl Backpex.ItemAction
        def cancel_label(_assigns), do: Backpex.translate("Cancel")

        @impl Backpex.ItemAction
        def handle(socket, items, params) do
          datetime = DateTime.truncate(DateTime.utc_now(), :second)
          socket =
            try do
              {:ok, _items} =
                Backpex.Resource.update_all(
                  socket.assigns,
                  items,
                  [set: [deleted_at: datetime, reason: Map.get(params, "reason")]],
                  "deleted"
                )

              socket
              |> clear_flash()
              |> put_flash(:info, "Item(s) successfully deleted.")
            rescue
                socket
                |> clear_flash()
                |> put_flash(:error, error)
            end

          {:noreply, socket}
      end

      # in your resource configuration file

      @impl Backpex.LiveResource
      def item_actions([show, edit, _delete]) do
        Enum.concat([show, edit],
          soft_delete: %{module: DemoWeb.ItemAction.SoftDelete}
        )
      end
  '''

  @doc """
  Action icon
  """
  @callback icon(assigns :: map()) :: %Phoenix.LiveView.Rendered{}

  @doc """
  A list of fields to be displayed in the item action. See `Backpex.Field`. In addition you have to provide
  a `type` for each field in order to support changeset generation.

  The following fields are currently not supported:

  - `Backpex.Fields.BelongsTo`
  - `Backpex.Fields.HasMany`
  - `Backpex.Fields.HasManyThrough`
  - `Backpex.Fields.Upload`
  """
  @callback fields() :: list()

  @doc """
  Initial change. The result will be passed to `Backpex.ItemAction.changeset/3` in order to generate a changeset.

  This function is optional and can be used to use changesets with schemas in item actions. If this function
  is not provided a changeset will be generated automatically based on the provided types in `Backpex.ItemAction.fields/0`.
  """
  @callback init_change() ::
              Ecto.Schema.t()
              | Ecto.Changeset.t()
              | {Ecto.Changeset.data(), Ecto.Changeset.types()}

  @doc """
  The changeset to be used in the resource action. It may be used to validate form inputs.

  Additional metadata is passed as a keyword list via the third parameter.

  The list of metadata:
  - `:assigns` - the assigns
  - `:target` - the name of the `form` target that triggered the changeset call. Default to `nil` if the call was not triggered by a form field.
  """
  @callback changeset(
              change ::
                Ecto.Schema.t()
                | Ecto.Changeset.t()
                | {Ecto.Changeset.data(), Ecto.Changeset.types()},
              attrs :: map(),
              metadata :: keyword()
            ) :: Ecto.Changeset.t()

  @doc """
  Action label (Show label on hover)
  """
  @callback label(assigns :: map()) :: binary()

  @doc """
  Confirm button label
  """
  @callback confirm_label(assigns :: map()) :: binary()

  @doc """
  cancel button label
  """
  @callback cancel_label(assigns :: map()) :: binary()

  @doc """
  This text is being displayed in the confirm dialog.

  There won't be any confirmation when this function is not defined.
  """
  @callback confirm(assigns :: map()) :: binary()

  @doc """
  Performs the action.
  """
  @callback handle(socket :: Phoenix.LiveView.Socket.t(), items :: list(map()), params :: map()) ::
              {:noreply, Phoenix.LiveView.Socket.t()} | {:reply, map(), Phoenix.LiveView.Socket.t()}

  @optional_callbacks confirm: 1, confirm_label: 1, cancel_label: 1, changeset: 3, fields: 0

  @doc """
  Defines `Backpex.ItemAction` behaviour and provides default implementations.
  """
  defmacro __using__(_) do
    quote do
      @before_compile Backpex.ItemAction
      @behaviour Backpex.ItemAction

      @impl Backpex.ItemAction
      def init_change do
        types = Backpex.Field.changeset_types(fields())

        {%{}, types}
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @impl Backpex.ItemAction
      def confirm_label(_assigns), do: Backpex.translate("Apply")

      @impl Backpex.ItemAction
      def cancel_label(_assigns), do: Backpex.translate("Cancel")

      @impl Backpex.ItemAction
      def fields, do: []

      @impl Backpex.ItemAction
      def changeset(_change, _attrs, _metadata), do: Ecto.Changeset.change(init_change())
    end
  end
end
