defmodule Backpex.HTML.CoreComponents do
  @moduledoc """
  Provides core components for Backpex.
  """
  use BackpexWeb, :html

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
        <:trigger class="btn btn-primary btn-sm" aria_label="User Menu">
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
  attr :readonly, :boolean, default: false, doc: "whether the dropdown is readonly"
  attr :class, :any, default: nil, doc: "additional classes for the outer container element"

  slot :trigger, doc: "the trigger element to be used to toggle the dropdown menu" do
    attr :class, :any, doc: "additional classes for the wrapper of the trigger"
    attr :aria_label, :string, doc: "accessible label for screen readers"
    attr :aria_labelledby, :string, doc: "accessible labelledby for screen readers"
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

    trigger_class = (assigns.trigger && assigns.trigger[:class]) || ""

    trigger_class =
      if assigns.readonly do
        ["cursor-not-allowed bg-base-200"] ++
          (trigger_class
           |> Enum.join(" ")
           |> String.split()
           |> List.delete("bg-transparent")
           |> List.delete("input"))
      else
        trigger_class
      end

    assigns = assign(assigns, trigger_class: trigger_class)

    ~H"""
    <div id={@id} class={[not @readonly && "dropdown", @class]} {@rest}>
      <div
        id={"#{@id}-trigger"}
        role="button"
        tabindex="0"
        aria-haspopup="true"
        aria-label={@trigger && @trigger[:aria_label]}
        aria-labelledby={@trigger && Map.get(@trigger, :aria_labelledby)}
        class={@trigger_class}
      >
        {render_slot(@trigger)}
      </div>

      <div
        :if={not @readonly}
        id={"#{@id}-menu"}
        tabindex="-1"
        aria-labelledby={"#{@id}-trigger"}
        class={[
          "menu dropdown-content z-1 bg-base-100 rounded-box outline-black/5 shadow outline-[length:var(--border)]",
          @menu && @menu[:class]
        ]}
      >
        {render_slot(@menu)}
      </div>
    </div>
    """
  end
end
