defmodule Backpex.ItemAction do
  @moduledoc """
  Behaviour implemented by all item actions.
  """

  @doc """
  Action icon
  """
  @callback icon(assigns :: map(), item :: struct()) :: %Phoenix.LiveView.Rendered{}

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
  The base item / schema to use for the changeset. The result will be passed as the first parameter to `c:changeset/3` each time it is called.


  This function is optional and can be used to use changesets with schemas in item actions. If this function is not provided,
  a schemaless changeset will be created with the provided types from `c:fields/0`.
  """
  @callback base_schema(assigns :: map()) ::
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
  @callback label(assigns :: map(), item :: struct() | nil) :: binary()

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
  Performs the action. It takes the socket, the list of affected items, and the casted and validated data (received from [`Ecto.Changeset.apply_action/2`](https://hexdocs.pm/ecto/Ecto.Changeset.html#apply_action/2)).

  You must return either `{:ok, socket}` or `{:error, changeset}`.

  If `{:ok, socket}` is returned, the action is considered successful by Backpex and the action modal is closed. However, you can add an error flash message to the socket to indicate that something has gone wrong.

  If `{:error, changeset}` is returned, the changeset is used to update the form to display the errors. Note that Backpex already validates the form for you.
  Therefore it is only necessary in rare cases to perform additional validation and return a changeset from `c:handle/3`.
  For example, if you are building a duplicate action and can only check for a unique constraint when inserting the duplicate element.

  You are only allowed to return `{:error, changeset}` if the action has a form. Otherwise Backpex will throw an ArgumentError.
  """
  @callback handle(socket :: Phoenix.LiveView.Socket.t(), items :: list(map()), params :: map() | struct()) ::
              {:ok, Phoenix.LiveView.Socket.t()} | {:error, Ecto.Changeset.t()}

  @optional_callbacks confirm: 1, confirm_label: 1, cancel_label: 1, changeset: 3, fields: 0

  @doc """
  Defines `Backpex.ItemAction` behaviour and provides default implementations.
  """
  defmacro __using__(_opts) do
    quote do
      @before_compile Backpex.ItemAction
      @behaviour Backpex.ItemAction

      require Backpex
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @impl Backpex.ItemAction
      def confirm_label(assigns), do: Backpex.__("Apply", assigns.live_resource)

      @impl Backpex.ItemAction
      def cancel_label(assigns), do: Backpex.__("Cancel", assigns.live_resource)

      @impl Backpex.ItemAction
      def fields, do: []

      @impl Backpex.ItemAction
      def changeset(_change, _attrs, metadata) do
        assigns = Keyword.get(metadata, :assigns)

        assigns
        |> base_schema()
        |> Ecto.Changeset.change()
      end

      @impl Backpex.ItemAction
      def base_schema(_assigns) do
        types = fields() |> Backpex.Field.changeset_types()

        {%{}, types}
      end
    end
  end

  @doc """
  Checks whether item action has confirmation modal.
  """
  def has_confirm_modal?(item_action) do
    module = Map.fetch!(item_action, :module)

    function_exported?(module, :confirm, 1)
  end

  @doc """
  Checks whether item action has form.
  """
  def has_form?(item_action) do
    module = Map.fetch!(item_action, :module)

    module.fields() != []
  end

  @doc """
  Returns default item actions.
  """
  def default_actions do
    [
      show: %{
        module: Backpex.ItemActions.Show,
        only: [:row]
      },
      edit: %{
        module: Backpex.ItemActions.Edit,
        only: [:row, :show]
      },
      delete: %{
        module: Backpex.ItemActions.Delete,
        only: [:row, :index, :show]
      }
    ]
  end
end
