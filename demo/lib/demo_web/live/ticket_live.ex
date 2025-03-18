defmodule DemoWeb.TicketLive do
  use Backpex.LiveResource,
    adapter: Backpex.Adapters.Ash,
    adapter_config: [
      resource: Demo.Helpdesk.Ticket
    ],
    layout: {DemoWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Ticket"

  @impl Backpex.LiveResource
  def plural_name, do: "Tickets"

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_page_title) do
    ~H"""
    <div role="alert" class="alert alert-info my-4 text-sm">
      <Backpex.HTML.CoreComponents.icon name="hero-information-circle" class="h-5 w-5" />
      <p>
        This resource uses the <strong>Ash adapter</strong>, which is currently in a very early alpha stage.
        Currently, only <strong>index</strong>, <strong>show</strong> and <strong>delete</strong> are functional in a
        very basic form. We are working on supporting more Backpex features in the future.
      </p>
    </div>
    """
  end

  @impl Backpex.LiveResource
  def can?(_assigns, action, _item) when action in [:index, :show, :delete], do: true
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def fields do
    [
      subject: %{
        module: Backpex.Fields.Text,
        label: "Subject",
        orderable: false
      },
      body: %{
        module: Backpex.Fields.Textarea,
        label: "Body",
        orderable: false,
        only: [:show]
      }
    ]
  end
end
