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
  The base schema to use for the changeset. The result will be passed as the first parameter to `c:changeset/3' each time it is called.


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
  Performs the action. It takes the socket and the casted and validated data (received from [`Ecto.Changeset.apply_action/2`](https://hexdocs.pm/ecto/Ecto.Changeset.html#apply_action/2)).
  """
  @callback handle(socket :: Phoenix.LiveView.Socket.t(), items :: list(map()), params :: map() | struct()) ::
              {:noreply, Phoenix.LiveView.Socket.t()} | {:reply, map(), Phoenix.LiveView.Socket.t()}

  @optional_callbacks confirm: 1, confirm_label: 1, cancel_label: 1, changeset: 3, fields: 0

  @doc """
  Defines `Backpex.ItemAction` behaviour and provides default implementations.
  """
  defmacro __using__(_) do
    quote do
      @before_compile Backpex.ItemAction
      @behaviour Backpex.ItemAction
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
      def changeset(_change, _attrs, metadata) do
        assigns = Keyword.get(metadata, :assigns)

        assigns
        |> base_schema()
        |> Ecto.Changeset.change()
      end

      @impl Backpex.ItemAction
      def base_schema(_assigns) do
        types = Backpex.Field.changeset_types(fields())

        {%{}, types}
      end
    end
  end
end
