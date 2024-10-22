defmodule DemoWeb.TicketLive do
  use Backpex.LiveResource,
    adapter: Backpex.Adapters.Ash,
    adapter_config: [
      resource: Demo.Helpdesk.Ticket
    ],
    layout: {DemoWeb.Layouts, :admin},
    pubsub: Demo.PubSub,
    topic: "tickets",
    event_prefix: "ticket_"

  @impl Backpex.LiveResource
  def singular_name, do: "Ticket"

  @impl Backpex.LiveResource
  def plural_name, do: "Tickets"

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_page_title) do
    ~H"""
    <div class="alert my-4 bg-blue-100 text-sm text-blue-800">
      <Backpex.HTML.CoreComponents.icon name="hero-information-circle" class="h-5 w-5" />
      <p>
        This resource uses the <strong>Ash adapter</strong> which is currently in a very early alpha stage.
        Currently only <strong>index</strong> and <strong>show</strong> are functional in a very basic form.
        We are working on supporting more Backpex features in the future.
      </p>
    </div>
    """
  end

  @impl Backpex.LiveResource
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, :show, _item), do: true
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def fields do
    [
      subject: %{
        module: Backpex.Fields.Text,
        label: "Subject"
      },
      body: %{
        module: Backpex.Fields.Textarea,
        label: "Body",
        only: [:show]
      }
    ]
  end
end
