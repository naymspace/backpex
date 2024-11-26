defmodule Backpex.ResourceAction do
  @moduledoc ~S'''
  Behaviour implemented by all resource action modules.

  > #### `use Backpex.ResourceAction` {: .info}
  >
  > When you `use Backpex.ResourceAction`, the `Backpex.ResourceAction` module will set `@behavior Backpex.ResourceAction`.
  > In addition it will implement the `c:base_item/1` function in order to generate a schemaless changeset by default.
  '''

  @doc """
  The title of the resource action. It will be part of the page header and slide over title.
  """
  @callback title() :: binary()

  @doc """
  The label of the resource action. It will be the label for the resource action button.
  """
  @callback label() :: binary()

  @doc """
  A list of fields to be displayed in the resource action. See `Backpex.Field`. In addition you have to provide
  a `type` for each field in order to support changeset generation.
  """
  @callback fields() :: list()

  @doc """
  The base schema to use for the changeset. The result will be passed as the first parameter to `c:changeset/3` each time it is called.


  This function is optional and can be used to use changesets with schemas in item actions. If this function is not provided,
  a schemaless changeset will be created with the provided types from `c:fields/0`.
  """
  @callback base_item(assigns :: map()) ::
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
  The handle function for the corresponding action. It receives the socket and casted and validated data (received from [`Ecto.Changeset.apply_action/2`](https://hexdocs.pm/ecto/Ecto.Changeset.html#apply_action/2)) and will be called when the form is valid and submitted.

  It must return either `{:ok, binary()}` or `{:error, binary()}`
  """
  @callback handle(socket :: Phoenix.LiveView.Socket.t(), data :: map()) ::
              {:ok, binary()} | {:error, binary()}

  @doc """
  Defines `Backpex.ResourceAction` behaviour.
  """
  defmacro __using__(_) do
    quote do
      @behaviour Backpex.ResourceAction

      @impl Backpex.ResourceAction
      def base_item(_assigns) do
        types = Backpex.Field.changeset_types(fields())

        {%{}, types}
      end

      defoverridable Backpex.ResourceAction
    end
  end

  @doc """
  Gets the name of a resource action.
  """
  def name(action, type), do: apply(Map.get(action, :module), type, [])
end
