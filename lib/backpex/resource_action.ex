defmodule Backpex.ResourceAction do
  @config_schema [
    module: [
      doc: "The resource action module, which implements the `Backpex.ResourceAction` behaviour.",
      type: :atom,
      required: true
    ]
  ]

  @moduledoc """
  Behaviour implemented by all resource action modules.

  ## Configuration

  `c:Backpex.LiveResource.resource_actions/0` returns a keyword list with one map per resource action. The key is the
  id of the action, used in its URL and passed to `c:Backpex.LiveResource.can?/3`. The map takes these options, any
  other key raises a configuration error when the index view loads:

  #{NimbleOptions.docs(@config_schema)}

  > #### `use Backpex.ResourceAction` {: .info}
  >
  > When you `use Backpex.ResourceAction`, the `Backpex.ResourceAction` module will set `@behavior Backpex.ResourceAction`.
  > In addition it will implement the `c:base_schema/1` function in order to generate a schemaless changeset by default.
  """

  alias Phoenix.LiveView.Socket

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
  Performs the action. It takes the socket and the casted and validated data (received from [`Ecto.Changeset.apply_action/2`](https://hexdocs.pm/ecto/Ecto.Changeset.html#apply_action/2)).

  You must return either `{:ok, socket}` or `{:error, changeset}`.

  If `{:ok, socket}` is returned, the action is considered successful by Backpex and the action modal is closed. However, you can add an error flash message to the socket to indicate that something has gone wrong.

  If `{:error, changeset}` is returned, the changeset is used to update the form to display the errors. Note that Backpex already validates the form for you. Therefore it is only necessary in rare cases to perform additional validation and return a changeset from `c:handle/2`.

  You have to use `Phoenix.LiveView.put_flash/3` along with the socket to show a success or error message.
  """
  @callback handle(socket :: Socket.t(), data :: map()) ::
              {:ok, Socket.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Defines `Backpex.ResourceAction` behaviour.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.ResourceAction

      @impl Backpex.ResourceAction
      def base_schema(_assigns) do
        types = Backpex.Field.changeset_types(fields())

        {%{}, types}
      end

      defoverridable Backpex.ResourceAction
    end
  end

  # Compiled once: `NimbleOptions.validate/2` validates a keyword list schema itself on every call.
  @compiled_config_schema NimbleOptions.new!(@config_schema)

  @doc false
  def validate_configs!(resource_actions, live_resource) do
    Backpex.LiveResource.Config.validate_each!(
      resource_actions,
      "resource action",
      "resource_actions/0",
      live_resource,
      &NimbleOptions.validate(&1, @compiled_config_schema)
    )
  end

  @doc """
  Gets the name of a resource action.
  """
  def name(action, type), do: apply(Map.get(action, :module), type, [])
end
