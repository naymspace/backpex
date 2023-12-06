defmodule Backpex.ResourceAction do
  @moduledoc ~S'''
  Behaviour implemented by all resource action modules.

  ## Example

      defmodule MyAppWeb.Actions.Invite do
        use Backpex.ResourceAction

        import Ecto.Changeset

        @impl Backpex.ResourceAction
        def title, do: "Invite user"

        @impl Backpex.ResourceAction
        def label, do: "Invite"

        @impl Backpex.ResourceAction
        def fields do
          [
            email: %{
              module: Backpex.Fields.Text,
              label: "Email",
              type: :string
            }
          ]
        end

        @impl Backpex.ResourceAction
        def changeset(change, attrs) do
          change
          |> cast(attrs, [:email])
          |> validate_required([:email]))
        end

        @impl Backpex.ResourceAction
        def handle(_socket, params) do
          # Send mail

          # Success
          {:ok, "An email to #{params[:email]} was sent successfully."}

          # Failure
          {:error, "An error occurred while sending an email to #{params[:email]}!"}
        end
      end

  > #### `use Backpex.ResourceAction` {: .info}
  >
  > When you `use Backpex.ResourceAction`, the `Backpex.ResourceAction` module will set `@behavior Backpex.ResourceAction`.
  > In addition it will implement the `Backpex.ResourceAction.init_change` function in order to generate a schemaless changeset by default.
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
  Initial change. The result will be passed to `Backpex.ResourceAction.changeset/2` in order to generate a changeset.

  This function is optional and can be used to use changesets with schemas in resource actions. If this function
  is not provided a changeset will be generated automatically based on the provided types in `Backpex.ResourceAction.fields/0`.
  """
  @callback init_change() ::
              Ecto.Schema.t()
              | Ecto.Changeset.t()
              | {Ecto.Changeset.data(), Ecto.Changeset.types()}

  @doc """
  The changeset to be used in the resource action. It may be used to validate form inputs.
  """
  @callback changeset(
              change ::
                Ecto.Schema.t()
                | Ecto.Changeset.t()
                | {Ecto.Changeset.data(), Ecto.Changeset.types()},
              attrs :: map()
            ) :: Ecto.Changeset.t()

  @doc """
  The handle function for the corresponding action. It receives the params and will be called when the form is valid and submitted.

  It must return either `{:ok, binary()}` or `{:error, binary()}`
  """
  @callback handle(socket :: Phoenix.LiveView.Socket.t(), params :: map()) ::
              {:ok, binary()} | {:error, binary()}

  @doc """
  Defines `Backpex.ResourceAction` behaviour.
  """
  defmacro __using__(_) do
    quote do
      @behaviour Backpex.ResourceAction

      @impl Backpex.ResourceAction
      def init_change do
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
