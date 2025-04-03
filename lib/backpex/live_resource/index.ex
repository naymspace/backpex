defmodule Backpex.LiveResource.Index do
  alias Backpex.Utils
  import Phoenix.Component

  def mount(_params, _session, socket, index_live_resource) do
    live_resource = Utils.parent_module(index_live_resource)

    socket =
      socket
      |> assign(:live_resource, live_resource)
      |> assign(:fluid?, live_resource.config(:fluid?))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="prose">
      <p>__MODULE__:<br />{__MODULE__}</p>
      <p>@live_resource:<br />{@live_resource}</p>
      <p>@live_action:<br />{@live_action}</p>
    </div>
    """
  end
end
