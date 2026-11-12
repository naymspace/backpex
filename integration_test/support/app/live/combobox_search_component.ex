defmodule Backpex.Test.ComboboxSearchComponent do
  @moduledoc """
  A LiveComponent with a combobox whose server search and form are handled by the component (`phx-target={@myself}`),
  for the browser tests of `Backpex.HTML.Combobox`. If the hook pushed the search to the LiveView instead, the
  LiveView would crash, as it has no handler for `search`.

  A query of `"slow"` takes 500 ms, so tests can see the loading state.
  """
  use Phoenix.LiveComponent

  import Backpex.HTML.Combobox

  @names ~w(Ada Alan Barbara Brian Grace Guido Linus René)

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, value: "", options: options(""), query: "", events: 0)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-2">
      <form id="component-form" phx-change="change" phx-target={@myself}>
        <.combobox
          id="component-person"
          name="component_person"
          label="Component person"
          value={@value}
          options={@options}
          selected_options={selected(@value)}
          on_search="search"
          search_debounce={50}
          phx-target={@myself}
        />
      </form>
      <p>Component value: <span id="component-value">{@value}</span></p>
      <p>Component query: <span id="component-query">{@query}</span></p>
      <p>Component searches: <span id="component-search-events">{@events}</span></p>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"query" => query, "id" => "component-person"}, socket) do
    if query == "slow", do: Process.sleep(500)

    socket
    |> assign(options: options(query), query: query)
    |> update(:events, &(&1 + 1))
    |> then(&{:noreply, &1})
  end

  def handle_event("change", %{"component_person" => value}, socket) do
    {:noreply, assign(socket, :value, value)}
  end

  defp selected(value), do: "" |> options() |> Enum.filter(&(&1.value == value))

  defp options(query) do
    query = String.downcase(query)

    @names
    |> Enum.filter(&(&1 |> String.downcase() |> String.contains?(query)))
    |> Enum.map(&%{label: &1, value: String.downcase(&1)})
  end
end
