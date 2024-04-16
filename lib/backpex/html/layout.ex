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
  slot(:inner_block)

  slot(:topbar, doc: "content to be displayed in the topbar") do
    attr(:class, :string, doc: "additional class that will be added to the component")
  end

  slot(:sidebar, doc: "content to be displayed in the sidebar") do
    attr(:class, :string, doc: "additional class that will be added to the component")
  end

  slot(:footer, doc: "content to be displayed in the footer")

  attr(:fluid, :boolean, default: false, doc: "toggles fluid layout")

  def app_shell(assigns) do
    ~H"""
    <div class="fixed inset-0 -z-10 h-full w-full bg-gray-100"></div>

    <div x-data="{ mobile_menu_open: false }">
      <div class="relative z-40 md:hidden" role="dialog" aria-modal="true" x-show="mobile_menu_open">
        <div class="fixed inset-0 bg-gray-600 bg-opacity-75"></div>

        <div class="fixed inset-0 z-40 flex">
          <div class="relative flex w-full max-w-xs flex-1 flex-col bg-white">
            <div class="absolute top-0 right-0 -mr-12 pt-2">
              <button
                type="button"
                class="ml-1 flex h-10 w-10 items-center justify-center rounded-full focus:outline-none focus:ring-2 focus:ring-inset focus:ring-white"
                @click="mobile_menu_open = false"
              >
                <Heroicons.x_mark solid class="h-5 w-5 text-white" />
              </button>
            </div>

            <div
              @click.outside="mobile_menu_open = false"
              class={"#{for sidebar <- @sidebar, do: sidebar[:class] || ""} h-0 flex-1 flex-col space-y-1 overflow-y-auto px-2 pt-5 pb-4"}
            >
              <%= render_slot(@sidebar) %>
            </div>
          </div>

          <div class="w-14 flex-shrink-0">
            <!-- Force sidebar to shrink to fit close icon -->
          </div>
        </div>
      </div>

      <div class="fixed top-0 z-10 hidden w-full md:block">
        <.topbar class={for topbar <- @topbar, do: topbar[:class] || ""}>
          <%= render_slot(@topbar) %>
        </.topbar>
      </div>

      <%= for sidebar <- @sidebar do %>
        <div class="hidden md:fixed md:inset-y-0 md:mt-16 md:flex md:w-64 md:flex-col">
          <div class="flex min-h-0 flex-1 flex-col">
            <div class={"#{sidebar[:class] || ""} flex flex-1 flex-col space-y-1 overflow-y-auto px-2 pt-5 pb-4"}>
              <%= render_slot(sidebar) %>
            </div>
          </div>
        </div>
      <% end %>

      <div class={"#{if length(@sidebar) > 0, do: "md:pl-64", else: ""} flex flex-1 flex-col"}>
        <div class="fixed top-0 z-50 w-full md:hidden">
          <.topbar class={for topbar <- @topbar, do: topbar[:class] || ""}>
            <%= render_slot(@topbar) %>
            <%= for _ <- @sidebar do %>
              <button
                type="button"
                class="-mt-0.5 -ml-0.5 inline-flex h-12 w-12 items-center justify-center rounded-md text-gray-800 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-gray-800"
                @click="mobile_menu_open = !mobile_menu_open"
              >
                <Heroicons.bars_3 solid class="h-8 w-8" />
              </button>
            <% end %>
          </.topbar>
        </div>
        <main class="h-[calc(100vh-4rem)] mt-[4rem] flex flex-col">
          <div class="flex-1">
            <div class={["mx-auto mt-5 px-4 sm:px-6 md:px-8", if(@fluid, do: "", else: "max-w-7xl")]}>
              <%= render_slot(@inner_block) %>
            </div>

            <%= render_slot(@footer) %>
            <.footer :if={@footer == []} />
          </div>
        </main>
      </div>
    </div>
    """
  end

  @doc """
  Renders a topbar.
  """
  @doc type: :component
  attr(:class, :string, default: "", doc: "additional class to be added to the component")

  slot(:inner_block)

  def topbar(assigns) do
    ~H"""
    <header class={"#{@class} flex h-16 w-full items-center justify-between border-b border-gray-200 bg-white px-4 text-gray-800"}>
      <%= render_slot(@inner_block) %>
    </header>
    """
  end

  @doc """
  Renders flash messages.
  """
  @doc type: :component
  attr(:flash, :map,
    required: true,
    doc: "flash map that will be passed to `Phoenix.LiveView.Helpers.live_flash/2`"
  )

  def flash_messages(assigns) do
    ~H"""
    <div
      :if={live_flash(@flash, :info) && live_flash(@flash, :info) != ""}
      class="alert my-4 bg-blue-100 text-sm text-blue-800"
      phx-value-key="info"
    >
      <Heroicons.information_circle class="h-5 w-5" />
      <span>
        <%= live_flash(@flash, :info) %>
      </span>
      <div>
        <button
          class="btn btn-square btn-sm btn-ghost"
          phx-click="lv:clear-flash"
          aria-label={Backpex.translate("Close alert")}
        >
          <Heroicons.x_mark class="h-5 w-5" />
        </button>
      </div>
    </div>

    <div
      :if={live_flash(@flash, :error) && live_flash(@flash, :error) != ""}
      class="alert my-4 bg-red-100 text-sm text-red-800"
      phx-value-key="error"
    >
      <Heroicons.x_circle class="h-5 w-5" />
      <span>
        <%= live_flash(@flash, :error) %>
      </span>
      <div>
        <button
          class="btn btn-square btn-sm btn-ghost"
          phx-click="lv:clear-flash"
          aria-label={Backpex.translate("Close alert")}
        >
          <Heroicons.x_mark class="h-5 w-5" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a footer. It provides a default look when no content is provided.
  """
  @doc type: :component
  attr(:class, :string, default: "", doc: "additional class that will be added to the component")

  slot(:inner_block)

  def footer(assigns) do
    ~H"""
    <footer class={"#{@class} flex justify-center py-8 text-sm"}>
      <%= render_slot(@inner_block) %>
      <div :if={@inner_block == []} class="flex flex-col items-center text-gray-500">
        <p>
          powered by
          <.link href="https://backpex.live" class="font-semibold hover:underline">Backpex <%= version() %></.link>
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
  attr(:class, :string, default: "", doc: "additional class that will be added to the component")
  attr(:title, :string, default: "Backpex", doc: "title that will be displayed next to the logo")
  attr(:hide_title, :boolean, default: false, doc: "if the title should be hidden")

  slot(:logo, doc: "the logo of the branding")

  def topbar_branding(assigns) do
    ~H"""
    <div class={"#{@class} flex flex-shrink-0 items-center space-x-2 text-gray-800"}>
      <%= if @logo === [] do %>
        <.backpex_logo class="w-8" />
      <% else %>
        <%= render_slot(@logo) %>
      <% end %>
      <%= unless @hide_title do %>
        <p class="font-semibold"><%= @title %></p>
      <% end %>
    </div>
    """
  end

  @doc """
  Get the Backpex logo SVG.
  """
  @doc type: :component
  attr(:class, :string,
    required: false,
    default: "",
    doc: "class that will be added to the SVG element"
  )

  def backpex_logo(assigns) do
    assigns = assign(assigns, :raw, backpex_logo_raw(assigns.class))
    ~H"<%= @raw %>"
  end

  # sobelow_skip ["Traversal.FileModule", "XSS.Raw"]
  defp backpex_logo_raw(class) do
    [:code.priv_dir(:backpex), "static", "images", "logo.svg"]
    |> Path.join()
    |> File.read!()
    |> Floki.parse_document!()
    |> Floki.find_and_update("svg", fn {"svg", attrs} ->
      {"svg", update_class(attrs, class)}
    end)
    |> Floki.raw_html()
    |> Phoenix.HTML.raw()
  end

  defp update_class(attrs, class) do
    Enum.map(attrs, fn
      {"class", _} -> {"class", class}
      other -> other
    end)
  end

  @doc """
  Renders a topbar dropdown.
  """
  @doc type: :component
  attr(:class, :string,
    required: false,
    default: "",
    doc: "additional class that will be added to the component"
  )

  slot(:label, required: true, doc: "label of the dropdown")

  def topbar_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <%= render_slot(@label) %>
      <ul tabindex="0" class="dropdown-content z-[1] menu bg-base-100 rounded-box w-52 p-2 shadow">
        <%= render_slot(@inner_block) %>
      </ul>
    </div>
    """
  end

  @doc """
  Container to wrap main elements and add margin.
  """
  attr(:class, :string, default: "", doc: "additional class that will be added to the component")
  slot(:inner_block)

  @doc type: :component
  def main_container(assigns) do
    ~H"""
    <div class={@class}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Renders a title.
  """
  @doc type: :component
  attr(:class, :string, default: "", doc: "additional class that will be added to the component")

  slot(:inner_block)

  def main_title(assigns) do
    ~H"""
    <h1 class={"#{@class} mb-2 text-3xl font-semibold leading-relaxed text-gray-800"}>
      <%= render_slot(@inner_block) %>
    </h1>
    """
  end

  @doc """
  Renders a sidebar section.
  """
  @doc type: :component
  attr(:class, :string, default: "", doc: "additional class that will be added to the component")

  attr(:id, :string,
    default: "section",
    doc:
      "The id for this section. It will be used to save and load the opening state of this section from local storage."
  )

  slot(:inner_block)
  slot(:label, required: true, doc: "label to be displayed on the section.")

  def sidebar_section(assigns) do
    ~H"""
    <div
      x-data={"{open: localStorage.getItem('section-opened-#{@id}')  === 'true'}"}
      x-init={"$watch('open', val => localStorage.setItem('section-opened-#{@id}', val))"}
    >
      <div @click="open = !open" class={"#{@class} group mt-2 flex cursor-pointer items-center space-x-1 p-2"}>
        <div class="pr-1">
          <Heroicons.chevron_down class="h-5 w-5 transition duration-75" solid x-bind:class="open ? '' : '-rotate-90'" />
        </div>
        <div class="flex gap-2 text-sm font-semibold uppercase text-gray-600">
          <%= render_slot(@label) %>
        </div>
      </div>
      <div class="flex-col space-y-1" x-show="open" x-transition x-transition.duration.75ms>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a sidebar item. It uses `Phoenix.Component.link/1` component, so you can can use link and href navigation.
  """
  @doc type: :component
  attr(:class, :string, default: "", doc: "additional class that will be added to the component")
  attr(:current_url, :string, doc: "the current url")
  attr(:navigate, :string)
  attr(:patch, :string)
  attr(:href, :any)

  slot(:inner_block)

  def sidebar_item(assigns) do
    path =
      case assigns do
        %{navigate: to} -> to
        %{patch: to} -> to
        %{href: href} -> href
      end

    highlight =
      if Router.active?(assigns.current_url, path) do
        "bg-gray-200 text-gray-900"
      else
        "text-gray-700 hover:bg-gray-50 hover:text-gray-900"
      end

    base_class = "group flex items-center gap-2 rounded-md px-2 py-2 space-x-2 hover:cursor-pointer"

    extra = assigns_to_attributes(assigns)

    assigns =
      assigns
      |> assign(:class, [base_class, highlight, assigns.class])
      |> assign(:extra, extra)

    ~H"""
    <.link class={@class} {@extra}>
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  @doc """
  Renders the form label and input with corresponding margin and alignment.
  """
  attr(:class, :string, default: "", doc: "extra classes to be added")

  slot :label, required: true do
    attr(:align, :atom, values: [:top, :center, :bottom])
  end

  slot(:inner_block)

  def field_container(assigns) do
    ~H"""
    <div class={"#{@class} flex flex-col items-stretch space-y-2 px-6 py-4 sm:flex-row sm:space-y-0 sm:py-3"}>
      <div :for={label <- @label} class={"#{get_align_class(label[:align])} hyphens-auto break-words pr-2 sm:w-1/4"}>
        <%= render_slot(@label) %>
      </div>

      <div class="w-full sm:w-3/4">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr(:title, :string, default: nil, doc: "modal title")
  attr(:target, :string, default: nil, doc: "live component for the close event to go to")
  attr(:close_event_name, :string, default: "close-modal", doc: "close event name")

  attr(:max_width, :string,
    default: "md",
    values: ["sm", "md", "lg", "xl", "2xl", "full"],
    doc: "modal max width"
  )

  attr(:open, :boolean, default: true, doc: "modal open")
  attr(:rest, :global)

  slot(:inner_block, required: false)

  def modal(assigns) do
    assigns =
      assigns
      |> assign(:classes, get_modal_classes(assigns))

    ~H"""
    <div id="modal">
      <div
        id="modal-overlay"
        class={[
          "animate-fade-in fixed inset-0 z-50 bg-gray-900 bg-opacity-30 transition-opacity",
          unless(@open, do: "hidden")
        ]}
        aria-hidden="true"
      >
      </div>
      <div
        id="modal-content"
        class={[
          "fixed inset-0 z-50 my-4 flex transform items-center justify-center overflow-hidden px-4 sm:px-6",
          unless(@open, do: "hidden")
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
          <div class="border-b border-gray-100 px-5 py-3">
            <div class="flex items-center justify-between">
              <div if={@title} class="0 text-2xl font-semibold text-gray-800">
                <%= @title %>
              </div>
              <button
                type="button"
                phx-click={hide_modal(@target, @close_event_name)}
                class="text-gray-400 hover:text-gray-500"
                aria-label={Backpex.translate("Close modal")}
              >
                <Heroicons.x_mark class="h-5 w-5" />
              </button>
            </div>
          </div>
          <!-- Content -->
          <div>
            <%= render_slot(@inner_block) %>
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
    base_classes = "animate-fade-in-scale w-full max-h-full overflow-auto bg-white rounded-xl shadow-lg"

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

  attr(:text, :string, doc: "text of the label")

  def input_label(assigns) do
    ~H"""
    <p class="text-content block break-words text-sm font-medium">
      <%= @text %>
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
