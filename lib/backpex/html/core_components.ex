defmodule Backpex.HTML.CoreComponents do
  @moduledoc """
  Provides core components for Backpex.
  """
  use BackpexWeb, :html

  require Backpex

  @doc """
  Renders a Heroicons icon.
  """
  @doc type: :component

  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global, default: %{"aria-hidden": "true", viewBox: "0 0 24 24", fill: "currentColor"}

  def icon(%{name: "hero-" <> _name} = assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest} />
    """
  end

  @doc """
  Renders a filter_badge component.
  """
  @doc type: :component

  attr :clear_event, :string, default: "clear-filter", doc: "event name for removing the badge"
  attr :filter_name, :string, required: true
  attr :label, :string, required: true
  attr :live_resource, :atom, default: nil

  slot :inner_block

  def filter_badge(assigns) do
    ~H"""
    <div class="indicator">
      <div class="join">
        <div class="btn btn-sm join-item bg-base-300 border-base-content/10 pointer-events-none font-semibold">
          {@label}
        </div>
        <div class="btn btn-sm btn-outline join-item border-base-content/10 pointer-events-none border-l-transparent">
          {render_slot(@inner_block)}
        </div>
      </div>
      <button
        type="button"
        phx-click={@clear_event}
        phx-value-field={@filter_name}
        class="indicator-item bg-base-300 rounded-selector grid cursor-pointer place-items-center p-1 shadow-sm transition duration-75 hover:text-secondary hover:scale-110"
        aria-label={Backpex.__({"Clear %{name} filter", %{name: @label}}, @live_resource)}
      >
        <.icon name="hero-x-mark" class="h-3 w-3" />
      </button>
    </div>
    """
  end
end
