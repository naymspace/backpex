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
  Renders a dropdown menu component with a trigger and menu content.

  ## Examples

      <.dropdown id="user-menu">
        <:trigger class="btn btn-primary btn-sm">
          User Menu
        </:trigger>
        <:menu>
          <li><.link navigate={~p"/profile"} class="menu-item">Profile</.link></li>
          <li><.link navigate={~p"/settings"}>Settings</.link></li>
          <li><.link navigate={~p"/logout"}>Logout</.link></li>
        </:menu>
      </.dropdown>
  """
  attr :id, :string, required: true, doc: "unique identifier for the dropdown"
  attr :class, :any, default: nil, doc: "additional classes for the outer container element"

  slot :trigger, doc: "the trigger element to be used to toggle the dropdown menu" do
    attr :class, :any, doc: "additional classes for the wrapper of the trigger"
  end

  slot :menu, doc: "the dropdown menu" do
    attr :class, :any, doc: "additional classes for the wrapper of the menu"
  end

  attr :rest, :global, include: ~w(phx-*)

  def dropdown(assigns) do
    assigns =
      assigns
      |> update(:trigger, fn
        [trigger] -> trigger
        _trigger -> nil
      end)
      |> update(:menu, fn
        [menu] -> menu
        _trigger -> nil
      end)

    ~H"""
    <div id={@id} class={["dropdown", @class]} {@rest}>
      <div id={"#{@id}-trigger"} role="button" tabindex="0" aria-haspopup="true" class={@trigger && @trigger[:class]}>
        {render_slot(@trigger)}
      </div>

      <div
        id={"#{@id}-menu"}
        role="button"
        tabindex="0"
        aria-labelledby={"#{@id}-trigger"}
        class={[
          "menu dropdown-content z-[1] bg-base-100 rounded-box outline-black/5 shadow outline-[length:var(--border)]",
          @menu && @menu[:class]
        ]}
      >
        {render_slot(@menu)}
      </div>
    </div>
    """
  end
end
