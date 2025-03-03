defmodule Backpex.HTML.Layout do
  @moduledoc """
  Contains all Backpex layout components.
  """

  use BackpexWeb, :html

  alias Backpex.Router

  @doc """
  Renders an app shell representing the base of your layout.
  """
  @doc type: :component

  attr :fluid, :boolean, default: false, doc: "toggles fluid layout"

  slot :inner_block

  slot :topbar, doc: "content to be displayed in the topbar" do
    attr :class, :string, doc: "additional class that will be added to the component"
  end

  slot :sidebar, doc: "content to be displayed in the sidebar" do
    attr :class, :string, doc: "additional class that will be added to the component"
  end

  slot :footer, doc: "content to be displayed in the footer"

  def app_shell(assigns) do
    ~H"""
    <div id="backpex-app-shell" class="drawer" phx-hook="BackpexSidebarSections">
      <input id="menu-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content">
        <div class="bg-base-200 fixed inset-0 -z-10 h-full w-full"></div>
        <div class={[
          "menu hidden overflow-y-scroll px-2 pt-5 pb-4 md:fixed md:inset-y-0 md:mt-16 md:block md:w-64",
          build_slot_class(@sidebar)
        ]}>
          {render_slot(@sidebar)}
        </div>

        <div class={["flex flex-1 flex-col", length(@sidebar) > 0 && "md:pl-64"]}>
          <div class="fixed top-0 z-30 block w-full md:-ml-64">
            <.topbar class={build_slot_class(@topbar)}>
              {render_slot(@topbar)}
              <label :if={@sidebar != []} for="menu-drawer" class="btn drawer-button btn-ghost ml-1 md:hidden">
                <Backpex.HTML.CoreComponents.icon name="hero-bars-3-solid" class="h-8 w-8" />
              </label>
            </.topbar>
          </div>
          <main class="h-[calc(100vh-4rem)] mt-[4rem]">
            <div class={["mx-auto mt-5 px-4 sm:px-6 md:px-8", !@fluid && "max-w-7xl"]}>
              {render_slot(@inner_block)}
            </div>
            {render_slot(@footer)}
            <.footer :if={@footer == []} />
          </main>
        </div>
      </div>
      <div class="drawer-side z-40">
        <label for="menu-drawer" class="drawer-overlay"></label>
        <div class={[
          "bg-base-100 menu min-h-full w-64 flex-1 flex-col overflow-y-auto px-2 pt-5 pb-4",
          build_slot_class(@sidebar)
        ]}>
          {render_slot(@sidebar)}
        </div>
      </div>
    </div>
    """
  end

  defp build_slot_class(slot), do: Enum.map(slot, &Map.get(&1, :class))

  @doc """
  Renders a topbar.
  """
  @doc type: :component

  attr :class, :string, default: "", doc: "additional class to be added to the component"

  slot :inner_block

  def topbar(assigns) do
    ~H"""
    <header class={["border-base-300 bg-base-100 text-base-content flex h-16 w-full items-center border-b px-4", @class]}>
      {render_slot(@inner_block)}
    </header>
    """
  end

  @doc """
  Renders flash messages.
  """
  @doc type: :component

  attr :flash, :map, required: true, doc: "flash map that will be passed to `Phoenix.Flash.get/2`"

  def flash_messages(assigns) do
    ~H"""
    <div
      :if={Phoenix.Flash.get(@flash, :info) && Phoenix.Flash.get(@flash, :info) != ""}
      class="alert bg-info text-info-content my-4 text-sm"
      phx-value-key="info"
    >
      <Backpex.HTML.CoreComponents.icon name="hero-information-circle" class="h-5 w-5" />
      <span>
        {Phoenix.Flash.get(@flash, :info)}
      </span>
      <div>
        <button
          class="btn btn-square btn-sm btn-ghost"
          phx-click="lv:clear-flash"
          aria-label={Backpex.translate("Close alert")}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-x-mark" class="h-5 w-5" />
        </button>
      </div>
    </div>

    <div
      :if={Phoenix.Flash.get(@flash, :error) && Phoenix.Flash.get(@flash, :error) != ""}
      class="alert bg-error text-error-content my-4 text-sm"
      phx-value-key="error"
    >
      <Backpex.HTML.CoreComponents.icon name="hero-x-circle" class="h-5 w-5" />
      <span>
        {Phoenix.Flash.get(@flash, :error)}
      </span>
      <div>
        <button
          class="btn btn-square btn-sm btn-ghost"
          phx-click="lv:clear-flash"
          aria-label={Backpex.translate("Close alert")}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-x-mark" class="h-5 w-5" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a footer. It provides a default look when no content is provided.
  """
  @doc type: :component

  attr :class, :string, default: "", doc: "additional class that will be added to the component"

  slot :inner_block

  def footer(assigns) do
    ~H"""
    <footer class={"#{@class} flex justify-center py-8 text-sm"}>
      {render_slot(@inner_block)}
      <div :if={@inner_block == []} class="text-base-content flex flex-col items-center">
        <p>
          powered by <.link href="https://backpex.live" class="font-semibold hover:underline">Backpex {version()}</.link>
        </p>
        <p>
          made by <.link href="https://naymspace.de" class="font-semibold hover:underline">Naymspace</.link>
        </p>
      </div>
    </footer>
    """
  end

  defp version, do: Application.spec(:backpex, :vsn) |> to_string()

  @doc """
  Renders the topbar branding.
  """
  @doc type: :component

  attr :class, :string, default: "", doc: "additional class that will be added to the component"
  attr :title, :string, default: "Backpex", doc: "title that will be displayed next to the logo"
  attr :hide_title, :boolean, default: false, doc: "if the title should be hidden"

  slot :logo, doc: "the logo of the branding"

  def topbar_branding(assigns) do
    ~H"""
    <div class={"#{@class} text-base-content flex shrink-0 flex-grow items-center space-x-2"}>
      <%= if @logo === [] do %>
        <.backpex_logo class="w-8" />
      <% else %>
        {render_slot(@logo)}
      <% end %>
      <%= unless @hide_title do %>
        <p class="font-semibold">{@title}</p>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a theme selector.
  """
  @doc type: :component

  attr :socket, :any, required: true

  attr :themes, :list,
    doc: "A list of tuples with {theme_label, theme_name} format",
    examples: [[{"Light", "light"}, {"Dark", "dark"}]]

  def theme_selector(assigns) do
    ~H"""
    <div
      id="backpex-theme-selector"
      phx-hook="BackpexThemeSelector"
      class="dropdown dropdown-bottom dropdown-end no-animation"
    >
      <div tabindex="0" role="button" class="btn btn-ghost m-1">
        <span class="hidden md:block">
          {Backpex.translate("Theme")}
        </span>
        <Backpex.HTML.CoreComponents.icon name="hero-swatch" class="h-5 w-5 md:hidden" />
        <Backpex.HTML.CoreComponents.icon name="hero-chevron-down" class="h-5 w-5" />
      </div>
      <form id="backpex-theme-selector-form" data-cookie-path={Router.cookie_path(@socket)}>
        <ul
          tabindex="0"
          class="dropdown-content bg-base-300 rounded-box z-[1] max-h-96 w-52 overflow-y-scroll p-2 shadow-2xl"
        >
          <li :for={{label, theme_name} <- @themes}>
            <input
              type="radio"
              name="theme-selector"
              class="theme-controller btn btn-sm btn-block btn-ghost justify-start"
              aria-label={label}
              phx-click={JS.dispatch("backpex:theme-change")}
              value={theme_name}
            />
          </li>
        </ul>
      </form>
    </div>
    """
  end

  @doc """
  Get the Backpex logo SVG.
  """
  @doc type: :component

  attr :class, :string, required: false, default: nil, doc: "class that will be added to the SVG element"

  def backpex_logo(assigns) do
    ~H"""
    <svg class={@class} clip-rule="evenodd" fill-rule="evenodd" viewBox="0 0 249 370">
      <g fill-rule="nonzero">
        <path
          fill="#d1f1ff"
          d="M135.45 117.583s17.57-2.37 33.79 9.8c16.22 12.16 28.04 32.1 29.4 57.44 1.35 25.34 3.38 71.29 3.38 100.01s-12.5 54.74-32.1 67.91c-19.6 13.17-57.44 17.91-88.86 12.16-31.42-5.74-53.72-10.47-63.52-20.61-9.8-10.14-10.14-22.98-10.14-35.48v-26.02s-4.73-7.43-4.73-16.56c0-9.12 2.7-44.6 2.7-70.62 0-26.02 7.77-46.97 29.39-61.49 21.62-14.53 33.45-14.19 36.83-20.61 3.38-6.42 3.38-27.37-1.35-34.13-4.73-6.76-8.22-11.26-5.07-17.57 3.89-7.77 20.61-11.15 42.57-11.15s31.42 7.77 33.45 15.2c2.03 7.43-7.43 11.83-8.78 22.64-1.35 10.83 3.04 29.08 3.04 29.08Z"
        /><path
          fill="#7384ad"
          d="M191.71 327.913s-15.37 18.08-31.25 13.35c-15.88-4.73-16.89-33.79-16.89-60.82s2.7-83.12 14.19-108.12c11.49-25 23.31-32.77 23.31-32.77s-3.21-4.39-5.91-7.43c0 0-15.96 9.21-27.11 38.86-11.15 29.65-14.28 69.26-14.28 113.19 0 43.92-1.01 57.1-6.42 65.55-5.41 8.45-20.1 10.98-42.57 8.78-20.18-1.97-55.07-6.76-55.07-6.76s10.3 5.75 41.72 11.15c31.42 5.41 52.2 6.08 78.73-1.69 26.51-7.78 34.28-22.98 41.55-33.29Z"
        /><path
          fill="#2d2e32"
          d="M111.17 369.523c-12.22 0-25.01-1.53-40.18-4.14-31.63-5.44-42.2-11.25-42.53-11.44l1.58-4.72c.02 0 8.71 1.19 19.95 2.63 11.23 1.44 24.99 3.13 35.03 4.11 5.01.49 9.61.74 13.77.74 7.13 0 12.99-.74 17.4-2.19 4.43-1.45 7.33-3.53 9.02-6.18 2.39-3.74 3.93-8.65 4.85-18.34.91-9.66 1.17-23.9 1.17-45.84.01-44.05 3.1-83.88 14.44-114.08 11.36-30.25 27.82-39.94 28.22-40.16l1.79-1.03 1.37 1.54c2.83 3.19 6.04 7.59 6.06 7.62l1.57 2.15-2.23 1.46c-.01.01-.03.02-.07.05l-.33.24c-.3.23-.76.59-1.36 1.11-1.2 1.04-2.95 2.71-5.07 5.15-4.23 4.89-9.93 12.87-15.58 25.16-5.51 11.95-9.1 32.11-11.19 52.5-2.1 20.41-2.77 41.13-2.77 54.56 0 10.11.15 20.46 1.14 29.6.98 9.14 2.88 17.06 6.04 22.2 2.12 3.44 4.63 5.61 7.9 6.59 1.59.47 3.17.68 4.75.68 5.62.02 11.28-2.79 15.68-5.93 4.39-3.13 7.47-6.5 8.07-7.19.08-.09.11-.12.11-.12l4 3.1c-3.55 5.02-7.42 11.61-13.85 17.94-6.43 6.33-15.44 12.33-29.06 16.32-13.96 4.09-26.47 5.9-39.66 5.9-.01.01-.02.01-.03.01Zm-39.32-9.14c15.03 2.59 27.53 4.07 39.32 4.07 12.74 0 24.68-1.72 38.26-5.69 12.9-3.79 21.04-9.28 26.94-15.07.82-.81 1.6-1.63 2.35-2.45-3.79 1.92-8.13 3.32-12.8 3.33a21.6 21.6 0 0 1-6.19-.89c-4.67-1.38-8.24-4.62-10.78-8.8-2.56-4.2-4.23-9.38-5.39-15.17-2.3-11.59-2.54-25.71-2.54-39.27 0-13.6.68-34.44 2.8-55.08 2.14-20.66 5.65-41.04 11.62-54.1 8.88-19.35 18.06-28.7 22.1-32.18-.14-.18-.28-.37-.44-.57-.71-.92-1.56-1.99-2.41-3.02-.2.15-.42.32-.65.5-1.56 1.24-3.8 3.22-6.4 6.11-5.18 5.78-11.79 15.22-17.25 29.75-10.96 29.1-14.12 68.5-14.11 112.3 0 21.98-.25 36.29-1.19 46.31-.94 9.99-2.61 15.89-5.63 20.6-2.49 3.9-6.56 6.58-11.71 8.26-5.17 1.68-11.5 2.44-18.97 2.44-4.37 0-9.12-.26-14.26-.76-6.81-.67-15.26-1.65-23.49-2.66 3.29.68 6.89 1.37 10.82 2.04Z"
        /><path
          fill="#2d2e32"
          d="M145.25 116.913s21.29-24.33 43.92-22.64c22.64 1.69 46.29 21.96 55.75 51.36s-.34 74.67-42.91 133.8l-1.35-62.85s24.67-44.26 13.52-89.88c0 0-9.46-1.35-31.09 13.85 0 .01-12.5-16.21-37.84-23.64Z"
        /><path
          fill="#7384ad"
          d="M228.2 125.183s-21.96-10.81-47.64 11.66l-4.22-4.39s17.4-15.04 37.17-17.4c0 0-12.16-11.83-30.41-9.8-18.25 2.03-27.71 13.68-27.71 13.68l-3.21-.51s17.23-18.75 34.97-18.75 33.95 15.38 41.05 25.51Zm-7.1 2.71s14.36 40.8-20.1 101.87l1.52 39.28s29.46-35.17 38.26-84.89c8.62-48.66-19.68-56.26-19.68-56.26ZM5.37 218.613s29.73-4.73 66.9-.34c37.17 4.39 49.33 10.14 49.33 22.98v37.5c0 16.55-6.67 16.3-35.39 10.56s-39.28-8.87-77.79-6.5c0 0-5.58-2.37-5.58-18.84-.01-12.42 2.53-45.36 2.53-45.36Z"
        /><path
          fill="#2d2e32"
          d="M85.71 291.793c-22.23-4.45-33.24-7.25-54.67-7.25-6.38 0-13.68.25-22.47.79l-.59.04-.55-.23c-.49-.19-2.41-1.26-4.04-4.4-1.65-3.14-3.08-8.26-3.08-16.77 0-12.65 2.54-45.51 2.54-45.56l.15-1.99 1.98-.31c.1-.02 14.08-2.24 34.9-2.24 9.66 0 20.8.48 32.7 1.89 14.01 1.66 24.54 3.5 32.39 5.91 7.82 2.41 13.11 5.4 16.23 9.72 2.06 2.88 2.96 6.26 2.95 9.86v37.5c-.01 4.02-.35 7.26-1.49 9.99a9.99 9.99 0 0 1-6.16 5.76c-1.88.65-3.98.89-6.38.89-5.82-.01-13.56-1.44-24.41-3.6Zm.99-4.97c10.79 2.16 18.43 3.51 23.4 3.5 2.05 0 3.61-.23 4.73-.62 1.12-.4 1.79-.89 2.37-1.6 1.15-1.38 1.89-4.37 1.87-9.35v-37.5c-.01-2.82-.63-4.97-2.01-6.92-1.38-1.95-3.67-3.77-7.26-5.44-7.16-3.37-19.35-5.93-37.83-8.1-11.67-1.38-22.61-1.85-32.1-1.85-15.83 0-27.64 1.31-32.13 1.9-.23 3.03-.67 9.11-1.11 15.96-.63 9.76-1.26 21.11-1.26 27.17 0 6.99 1.05 11.16 2.08 13.53.68 1.54 1.32 2.34 1.71 2.72 8.46-.51 15.59-.75 21.88-.75h.06c21.88 0 33.58 2.95 55.6 7.35Z"
        /><path
          fill="#fff"
          d="M53.26 139.543c3.57 3.27-12.38 3.13-19.47 15.54-7.1 12.42-8.15 30.58-8.15 30.58s-4.05-25.09 1.01-34.97c5.07-9.88 20.53-16.72 26.61-11.15Z"
        /><path
          fill="#2d2e32"
          d="M99.63 136.253c-45.65 0-61.94-2.03-62.05-2.04l.44-3.52s.23.03.75.08 1.32.13 2.43.23c2.21.19 5.65.44 10.51.69 9.72.5 25.15 1.01 47.93 1.01 43.88 0 61.77-11.32 62.58-11.84l.03-.02 1.99 2.94c-.29.2-18.66 12.47-64.56 12.47h-.05Z"
        /><path
          fill="#2d2e32"
          d="M104.63 122.683s-10.79-6.88-19.69-5.93c-8.9.95-12.95 9.49-12.95 9.49l22.42 2.2s-5.57 2.82-13.79 2.79c-4.45-.02-13.76-1.19-13.76-1.19s-1.08-9.97 8.9-14.95c9.98-4.98 26.98 2.85 26.98 2.85s6.78-4.46 15.92-5.22c11.33-.95 17.8 11.87 17.8 11.87s-18.7-17.42-31.83-1.91Zm-40.01-51.66 1.11-2.83s.21.08.65.24c.44.16 1.1.38 1.96.66 1.72.54 4.24 1.28 7.42 2.01 6.35 1.47 15.33 2.93 25.77 2.93 11.77 0 25.4-1.86 39.25-7.68l1.18 2.8c-14.3 6-28.33 7.92-40.43 7.92-21.45-.01-36.8-6.01-36.91-6.05Z"
        /><path
          fill="#2d2e32"
          d="M80.6 367.403c-15.73-2.88-29.22-5.5-40.13-8.72-10.9-3.24-19.3-7.01-24.76-12.62-5.27-5.44-8.02-11.71-9.4-18.08-1.38-6.38-1.45-12.89-1.45-19.16v-25.33c-1.2-2.1-4.7-8.87-4.73-17.24 0-4.75.68-15.83 1.36-29.1.68-13.25 1.35-28.59 1.35-41.51 0-13.26 1.98-25.37 6.81-36.1s12.54-20.01 23.7-27.5c8.24-5.54 15.13-8.98 20.65-11.43 5.51-2.44 9.65-3.93 12.19-5.39 1.71-.98 2.61-1.84 3.15-2.87.55-1.02 1.14-3.07 1.51-5.55.38-2.49.58-5.45.58-8.47 0-3.58-.29-7.26-.87-10.41-.56-3.14-1.49-5.77-2.41-7.05-1.72-2.47-3.34-4.69-4.59-6.96-1.24-2.27-2.15-4.67-2.15-7.33 0-1.92.49-3.9 1.48-5.86 1.28-2.54 3.47-4.51 6.21-6.09 2.75-1.57 6.1-2.78 9.96-3.73 7.72-1.89 17.55-2.73 28.67-2.73 11.28 0 19.54 1.98 25.4 5.11 5.85 3.12 9.28 7.48 10.5 11.96.25.92.37 1.84.37 2.73 0 2.11-.67 3.99-1.53 5.65-.87 1.67-1.94 3.19-2.98 4.74-2.09 3.1-4.04 6.25-4.58 10.5-.16 1.31-.24 2.78-.24 4.35-.01 7.65 1.81 17.3 2.73 21.56l.03.15c.5-.02 1.08-.03 1.72-.03 6.34 0 19.29 1.28 31.59 10.49 16.81 12.6 29.02 33.27 30.41 59.33 1.35 25.37 3.38 71.32 3.38 100.15-.02 29.44-12.76 56.22-33.22 70.02-14.8 9.9-38.6 14.97-62.72 15-9.46-.04-18.97-.83-27.99-2.48Zm5.44-312.74c-6.18.97-11.16 2.47-14.41 4.35-2.18 1.25-3.53 2.61-4.2 3.96-.69 1.39-.94 2.51-.94 3.59 0 1.48.5 3.01 1.53 4.89 1.02 1.87 2.54 4 4.29 6.49 1.64 2.38 2.58 5.5 3.25 9.04.65 3.54.95 7.48.95 11.33 0 3.25-.21 6.43-.64 9.24-.44 2.81-1.04 5.23-2.04 7.15-1.14 2.18-2.99 3.69-5.12 4.91-2.15 1.22-4.68 2.25-7.72 3.52-6.06 2.53-14.18 5.97-24.82 13.11-10.46 7.04-17.45 15.49-21.91 25.38-4.46 9.88-6.36 21.25-6.36 34.01 0 13.09-.68 28.49-1.36 41.77-.68 13.25-1.35 24.47-1.35 28.84-.03 7.73 3.89 14.51 4.3 15.15.03.04.03.05.03.05l.4.62v26.76c0 6.23.1 12.39 1.34 18.09 1.25 5.71 3.56 10.93 8.09 15.63 4.34 4.53 11.99 8.18 22.55 11.28 10.54 3.11 23.91 5.73 39.61 8.6 8.69 1.59 17.91 2.36 27.1 2.36 23.38.03 46.55-5.12 59.9-14.14 18.74-12.56 30.99-37.81 30.98-65.81 0-28.61-2.02-74.57-3.38-99.88-1.32-24.62-12.76-43.82-28.39-55.55-11.06-8.31-22.86-9.48-28.55-9.48-1.65 0-2.78.1-3.2.14-.14.02-.18.02-.18.02l-2.27.31-.53-2.22c-.01-.1-3.36-13.83-3.37-24.99 0-1.72.08-3.4.28-4.97.51-4.13 2.1-7.44 3.76-10.15 1.66-2.71 3.37-4.91 4.33-6.78.65-1.25.96-2.29.96-3.32 0-.44-.06-.9-.19-1.4-.81-2.95-3.12-6.2-8-8.82-4.87-2.61-12.32-4.52-23.01-4.511-8.14-.02-15.53.46-21.71 1.43Zm49.41 62.92 2.46-.59-2.46.59Z"
        /><path
          fill="#7384ad"
          d="m190.12 127.893-9.03.92s-6.81 4.4-12.89 12.77c-6.08 8.36 2.81 4.22 2.81 4.22s7.96-9.04 18.35-15.37c10.39-6.34.76-2.54.76-2.54Z"
        /><path
          fill="#7384ad"
          stroke="#2d2e32"
          stroke-width="5"
          d="M103.39 2.673c-15.94-.88-32.01 8.5-31.96 10.38.05 1.89 7.06 45.73 8.05 48.32.89 2.33 12.54 4.65 23.91 5.11 11.36-.45 23.01-2.78 23.91-5.11.99-2.59 8-46.44 8.05-48.32.06-1.88-16.02-11.26-31.96-10.38Z"
        /><path
          fill="#2d2e32"
          d="M103.99 292.393s8.45 26.52 9.46 30.32c1.01 3.8-7.1 8.87-9.12 6.59-2.03-2.28-11.15-27.87-12.67-32.94-1.52-5.07 0-5.57 0-5.57l12.33 1.6Zm-71.41-35.8c0 4.51-3.66 8.16-8.16 8.16s-8.16-3.66-8.16-8.16 3.66-8.16 8.16-8.16 8.16 3.65 8.16 8.16Zm69.98 5.48c0 4.51-3.66 8.16-8.16 8.16-4.51 0-8.16-3.66-8.16-8.16s3.66-8.16 8.16-8.16 8.16 3.65 8.16 8.16Z"
        /><path
          fill="#2d2e32"
          d="M23.87 309.393c-1.7-.4-2.9-1.93-2.9-3.67v-46.22c0-2.08 1.69-3.77 3.77-3.77s3.77 1.69 3.77 3.77v30.31l4.02-8.01c.93-1.86 3.2-2.61 5.06-1.68 1.86.93 2.61 3.2 1.68 5.06l-11.16 22.23a3.784 3.784 0 0 1-4.24 1.98Zm74.24-19.48c0 2.11-1.22 3.82-2.73 3.82h-1.97c-1.51 0-2.73-1.71-2.73-3.82v-25.89c0-2.11 1.22-3.82 2.73-3.82h1.97c1.51 0 2.73 1.71 2.73 3.82v25.89Z"
        />
      </g>
    </svg>
    """
  end

  @doc """
  Renders a topbar dropdown.
  """
  @doc type: :component

  attr :class, :string, required: false, default: "", doc: "additional class that will be added to the component"

  slot :label, required: true, doc: "label of the dropdown"

  def topbar_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      {render_slot(@label)}
      <ul tabindex="0" class="dropdown-content z-[1] menu bg-base-100 rounded-box w-52 p-2 shadow">
        {render_slot(@inner_block)}
      </ul>
    </div>
    """
  end

  @doc """
  Container to wrap main elements and add margin.
  """
  @doc type: :component

  attr :class, :string, default: "", doc: "additional class that will be added to the component"
  slot :inner_block

  def main_container(assigns) do
    ~H"""
    <div class={@class}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a title.
  """
  @doc type: :component

  attr :class, :string, default: "", doc: "additional class that will be added to the component"

  slot :inner_block

  def main_title(assigns) do
    ~H"""
    <h1 class={"#{@class} text-base-content mb-2 text-3xl font-semibold leading-relaxed"}>
      {render_slot(@inner_block)}
    </h1>
    """
  end

  @doc """
  Renders a sidebar section.
  """
  @doc type: :component

  attr :class, :string, default: nil, doc: "additional class that will be added to the component"

  attr :id, :string,
    default: "section",
    doc:
      "The id for this section. It will be used to save and load the opening state of this section from local storage."

  slot :inner_block
  slot :label, required: true, doc: "label to be displayed on the section."

  def sidebar_section(assigns) do
    ~H"""
    <li data-section-id={@id} class={["hidden", @class]}>
      <span data-menu-dropdown-toggle class="menu-dropdown-toggle menu-dropdown-show">
        {render_slot(@label)}
      </span>
      <ul data-menu-dropdown-content class="menu-dropdown menu-dropdown-show">
        {render_slot(@inner_block)}
      </ul>
    </li>
    """
  end

  @doc """
  Renders a sidebar item. It uses `Phoenix.Component.link/1` component, so you can can use link and href navigation.
  """
  @doc type: :component

  attr :class, :string, default: "", doc: "additional class that will be added to the component"
  attr :current_url, :string, doc: "the current url"
  attr :navigate, :string
  attr :patch, :string
  attr :href, :any

  slot :inner_block

  def sidebar_item(assigns) do
    path =
      case assigns do
        %{navigate: to} -> to
        %{patch: to} -> to
        %{href: href} -> href
      end

    assigns =
      assigns
      |> assign(:active, Router.active?(assigns.current_url, path))
      |> assign(:extra, assigns_to_attributes(assigns))

    ~H"""
    <li>
      <.link class={[@class, @active && "active"]} {@extra}>
        {render_slot(@inner_block)}
      </.link>
    </li>
    """
  end

  @doc """
  Renders the form label and input with corresponding margin and alignment.
  """
  @doc type: :component

  attr :class, :string, default: "", doc: "extra classes to be added"

  slot :label, required: true do
    attr :align, :atom, values: [:top, :center, :bottom]
  end

  slot :inner_block

  def field_container(assigns) do
    ~H"""
    <div class={"#{@class} flex flex-col items-stretch space-y-2 px-6 py-4 sm:flex-row sm:space-y-0 sm:py-3"}>
      <div :for={label <- @label} class={"#{get_align_class(label[:align])} hyphens-auto break-words pr-2 sm:w-1/4"}>
        {render_slot(@label)}
      </div>

      <div class="w-full sm:w-3/4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal.
  """
  @doc type: :component

  attr :title, :string, default: nil, doc: "modal title"
  attr :target, :string, default: nil, doc: "live component for the close event to go to"
  attr :close_event_name, :string, default: "close-modal", doc: "close event name"
  attr :max_width, :string, default: "md", values: ["sm", "md", "lg", "xl", "2xl", "full"], doc: "modal max width"
  attr :open, :boolean, default: true, doc: "modal open"
  attr :rest, :global

  slot :inner_block, required: false

  def modal(assigns) do
    assigns =
      assigns
      |> assign(:classes, get_modal_classes(assigns))

    ~H"""
    <div id="modal">
      <div
        id="modal-overlay"
        class={["animate-fade-in bg-neutral/40 fixed inset-0 z-50 transition-opacity", if(!@open, do: "hidden")]}
        aria-hidden="true"
      >
      </div>
      <div
        id="modal-content"
        class={[
          "fixed inset-0 z-50 my-4 flex transform items-center justify-center overflow-hidden px-4 sm:px-6",
          if(!@open, do: "hidden")
        ]}
        role="dialog"
        aria-modal="true"
      >
        <div
          class={@classes}
          phx-click-away={@open && hide_modal(@target, @close_event_name)}
          phx-window-keydown={@open && hide_modal(@target, @close_event_name)}
          phx-key={@open && "escape"}
        >
          <!-- Header -->
          <div class="border-base-200 border-b px-5 py-3">
            <div class="flex items-center justify-between">
              <div if={@title} class="0 text-base-content text-2xl font-semibold">
                {@title}
              </div>
              <button
                type="button"
                phx-click={hide_modal(@target, @close_event_name)}
                class="text-base-content/50 hover:text-base-content"
                aria-label={Backpex.translate("Close modal")}
              >
                <Backpex.HTML.CoreComponents.icon name="hero-x-mark" class="h-5 w-5" />
              </button>
            </div>
          </div>
          <!-- Content -->
          <div>
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  def hide_modal(target \\ nil, close_event)

  def hide_modal(_target, nil) do
    %JS{}
    |> JS.hide(to: "#modal-overlay")
    |> JS.hide(to: "#modal-content")
  end

  def hide_modal(target, close_event) do
    case target do
      nil ->
        JS.push(%JS{}, close_event)

      target ->
        JS.push(%JS{}, close_event, target: target)
    end
  end

  defp get_modal_classes(assigns) do
    base_classes = "animate-fade-in-scale w-full max-h-full overflow-auto bg-base-100 rounded-box shadow-lg"

    max_width_class =
      case Map.get(assigns, :max_width, "md") do
        "sm" -> "max-w-sm"
        "md" -> "max-w-xl"
        "lg" -> "max-w-3xl"
        "xl" -> "max-w-5xl"
        "2xl" -> "max-w-7xl"
        "full" -> "max-w-full"
      end

    [base_classes, max_width_class]
  end

  @doc """
  Renders a text to be used as a label for an input.
  """
  @doc type: :component

  attr :text, :string, doc: "text of the label"

  def input_label(assigns) do
    ~H"""
    <p class="text-content block break-words text-sm font-medium">
      {@text}
    </p>
    """
  end

  @doc """
  Filters fields by certain panel.

  ## Examples

      iex> Backpex.HTML.Layout.visible_fields_by_panel([field1: %{panel: :default}, field2: %{panel: :panel}], :default, nil)
      [field1: %{panel: :default}]

      iex> Backpex.HTML.Layout.visible_fields_by_panel([field1: %{panel: :default, visible: fn _assigns -> false end}, field2: %{panel: :panel}], :default, nil)
      []

      iex> Backpex.HTML.Layout.visible_fields_by_panel([field1: %{panel: :default}], :panel, nil)
      []
  """
  def visible_fields_by_panel(fields, panel, assigns) do
    fields
    |> Keyword.filter(fn {_name, field_options} ->
      get_panel(field_options) == panel and visible?(field_options, assigns)
    end)
  end

  defp get_panel(%{panel: panel} = _field), do: panel
  defp get_panel(_field), do: :default

  defp visible?(%{visible: visible} = _field_options, assigns), do: visible.(assigns)
  defp visible?(_field_options, _assigns), do: true

  defp get_align_class(align) do
    case align do
      :top -> "sm:self-start"
      :center -> "sm:self-center"
      :bottom -> "sm:self-end"
      _align -> "sm:self-center"
    end
  end
end
