defmodule Backpex.Filter do
  @moduledoc ~S'''
  The base behaviour for all filters. Injects also basic layout, form and delete button for a filters rendering.

  Enabling filters on a resources index view is a two step process:

  1. Add modules implementing one of the behaviors from the `Backpex.Filters` namespace to your project.
    - We suggest to use a `MyAppWeb.Filters.<FILTERNAME>` convention.
    - We implemented the `__using__` macro for the filters, injecting code like imports (e.g. `Ecto.Query`) and functions (e.g. `render/1`) into your module.
  2. Implement the `filters/0` callback on your resource.

  The latter just returns a keyword list with the field names as keys and the filter module as values.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def filters, do: [
          status: %{
            module: MyAppWeb.Filters.EventStatusSelect
          },
          begins_at: %{
            module: MyAppWeb.Filters.DateRange
          },
          published: %{
            module: MyAppWeb.Filters.EventPublished
          }
        ]

  ## Custom filters

  Instead of using the pre-defined filters you can also define custom filters by using `Backpex.Filter` and implementing at least `label/0`, `query/3`, `render/1` and `render_form/1`.

  For example purposes let's define a custom select filter:

      defmodule MyApp.Filters.CustomSelectFilter do
        use BackpexWeb, :filter

        @impl Backpex.Filter
        def label, do: "Event status"

        @impl Backpex.Filter
        def render(assigns) do
          assigns = assign(assigns, :label, option_value_to_label(options(), assigns.value))

          ~H"""
          <%= @label %>
          """
        end
      
        @impl Backpex.Filter
        def render_form(assigns) do
          ~H"""
          <.form_field
            type="select"
            selected={selected(@value)}
            options={my_options()}
            form={@form}
            field={@field}
            label=""
          />
          """
        end
        
        @impl Backpex.Filter
        def query(query, attribute, value) do
          where(query, [x], field(x, ^attribute) == ^value)
        end
        
        defp option_value_to_label(options, value) do
          Enum.find_value(options, fn {option_label, option_value} ->
            if option_value == value, do: option_label
          end)
        end
        
        defp my_options, do: [
          {"Select an option...", nil},
          {"Open", :open},
          {"Close", :close},
        ]

        defp selected(""), do: nil
        defp selected(value), do: value
      end

  ## Filter presets

  To define presets for your filters, you need to add a list of maps under the key of `:presets` to your filter in your LiveResource.

  Each of those maps has two keys:
    1. `:label` – simply the String shown to the user
    2. `:values` – a function with arity 0 that returns the values corresponding to your used filter

  > See the example below for `:values` return values for the default range and boolean filter


      @impl Backpex.LiveResource
      def filters, do: [
          begins_at: %{
            module: MyAppWeb.Filters.DateRange,
            presets: [
            %{
              label: "Last 7 Days",
              values: fn -> %{
                "start" => Date.add(Date.utc_today(), -7),
                "end" => Date.utc_today()
              }
              end
            }
          },
          published: %{
            module: MyAppWeb.Filters.EventPublished,
            presets: [
              %{
                label: "Both",
                values: fn -> [:published, :not_published] end
              },
              %{
                label: "Only published",
                values: fn -> [:published] end
              }
            ]
          }
        ]

  '''
  @doc """
  Defines whether the filter can be used or not.
  """
  @callback can?(Phoenix.LiveView.Socket.assigns()) :: boolean()

  @doc """
  The filter's label.
  """
  @callback label :: String.t()

  @doc """
  The filter query that is executed if an option was selected.
  """
  @callback query(Ecto.Query.t(), any(), any()) :: Ecto.Query.t()

  @doc """
  Renders the filters selected value(s).
  """
  @callback render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Renders the filters options form.
  """
  @callback render_form(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.Filter

      @impl Backpex.Filter
      def can?(_assigns), do: true

      defoverridable can?: 1
    end
  end
end
