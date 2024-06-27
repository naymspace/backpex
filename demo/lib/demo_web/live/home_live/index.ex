defmodule DemoWeb.HomeLive.Index do
  @moduledoc false

  use DemoWeb, :live_view
  alias Demo.Newsletter
  alias Demo.Newsletter.Contact

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    changeset = Newsletter.change_contact(%Contact{})

    socket =
      socket
      |> assign(:form_hidden?, form_hidden?())
      |> assign(:subscribed?, false)
      |> assign(:form, to_form(changeset))

    {:ok, socket}
  end

  defp form_hidden? do
    Application.fetch_env!(:demo, Demo.Newsletter.Brevo)[:api_key]
    |> Kernel.is_nil()
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"contact" => params}, socket) do
    form =
      %Contact{}
      |> Newsletter.change_contact(params)
      |> Map.put(:action, :insert)
      |> to_form()

    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl Phoenix.LiveView
  def handle_event("subscribe", %{"contact" => params}, socket) do
    case Newsletter.subscribe(params) do
      {:ok, _contact} -> {:noreply, assign(socket, :subscribed?, true)}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  attr :class, :string, default: ""
  slot(:inner_block, required: true)

  def section(assigns) do
    ~H"""
    <div class={["mx-auto max-w-7xl px-6 py-10 sm:py-24 lg:px-8", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def bg_pattern(assigns) do
    ~H"""
    <svg
      class="absolute inset-0 -z-10 h-full w-full stroke-gray-200 [mask-image:radial-gradient(100%_100%_at_top_right,white,transparent)]"
      aria-hidden="true"
    >
      <defs>
        <pattern id="bg-pattern" width="200" height="200" x="50%" y="-1" patternUnits="userSpaceOnUse">
          <path d="M.5 200V.5H200" fill="none" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" stroke-width="0" fill="url(#bg-pattern)" />
    </svg>
    """
  end

  def feature_list(assigns) do
    ~H"""
    <dl class="mt-20 grid grid-cols-1 gap-12 sm:grid-cols-2 sm:gap-x-6 lg:grid-cols-4 lg:gap-x-8">
      <div :for={feature <- @feature} class="relative">
        <dt>
          <Backpex.HTML.CoreComponents.icon name="hero-check" class="text-primary absolute mt-1 h-6 w-6" />
          <p class="ml-10 text-lg font-semibold leading-8 text-gray-900">
            <%= feature.title %>
          </p>
        </dt>
        <dd class="mt-2 ml-10 text-base leading-7 text-gray-600">
          <%= render_slot(feature) %>
        </dd>
      </div>
    </dl>
    """
  end
end
