defmodule Backpex.LiveResource.Form do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

  alias Backpex.Authorization
  alias Backpex.LiveResource
  alias Backpex.LiveResource.FormLiveNoticePrototype, as: Proto
  alias Backpex.Resource

  require Backpex

  def mount(params, _session, socket, live_resource) do
    live_action = socket.assigns.live_action

    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:fields, live_resource.fields(live_action, socket.assigns))
    |> assign(:params, params)
    |> assign(:page_title, page_title(live_resource, live_action))
    |> assign_return_to(params)
    |> assign_item(live_action)
    |> can?(live_resource, live_action)
    |> assign_changeset(live_action)
    |> maybe_init_prototype(live_action, live_resource)
    |> ok()
  end

  # PROTOTYPE (#2577): the edit form subscribes to PubSub like Show and Index do.
  defp maybe_init_prototype(socket, :edit, live_resource) do
    socket
    |> LiveResource.maybe_subscribe_to_pubsub(live_resource)
    |> Proto.init()
  end

  defp maybe_init_prototype(socket, _live_action, _live_resource), do: socket

  def handle_params(params, _url, %{assigns: %{proto: _proto}} = socket) do
    socket
    |> Proto.put_variant(params["variant"] || "banner")
    |> noreply()
  end

  def handle_params(_params, _url, socket) do
    noreply(socket)
  end

  def render(%{proto: _proto} = assigns) do
    assigns = assign(assigns, :proto_rows, Proto.rows(assigns))

    ~H"""
    {Backpex.HTML.Resource.resource_form(assigns)}
    <Proto.overlay proto={@proto} rows={@proto_rows} />
    """
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_form(assigns)
  end

  def handle_info({"backpex:updated", item}, %{assigns: %{proto: _proto}} = socket) do
    if Proto.same_item?(socket, item),
      do: socket |> Proto.handle_remote(item) |> noreply(),
      else: noreply(socket)
  end

  def handle_info({"backpex:deleted", item}, %{assigns: %{proto: _proto}} = socket) do
    if Proto.same_item?(socket, item),
      do: socket |> Proto.handle_remote(:deleted) |> noreply(),
      else: noreply(socket)
  end

  # credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
  def handle_info({:update_changeset, changeset}, socket) do
    socket
    |> assign(:changeset, changeset)
    |> noreply()
  end

  # credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
  def handle_info({:put_assoc, {key, value} = _assoc}, socket) do
    changeset = Ecto.Changeset.put_assoc(socket.assigns.changeset, key, value)
    assocs = Map.get(socket.assigns, :assocs, []) |> Keyword.put(key, value)

    socket
    |> assign(:assocs, assocs)
    |> assign(:changeset, changeset)
    |> noreply()
  end

  def handle_info(_event, socket) do
    noreply(socket)
  end

  def handle_event("proto-take-over", _params, socket), do: socket |> Proto.take_over_untouched() |> noreply()
  def handle_event("proto-discard", _params, socket), do: socket |> Proto.discard_mine() |> noreply()
  def handle_event("proto-dry-run", _params, socket), do: socket |> Proto.dry_run() |> noreply()
  def handle_event("proto-simulate", %{"what" => what}, socket), do: socket |> Proto.simulate(what) |> noreply()

  def handle_event("proto-use-theirs", %{"key" => key}, socket),
    do: socket |> Proto.use_theirs(String.to_existing_atom(key)) |> noreply()

  def handle_event("proto-keep-mine", %{"key" => key}, socket),
    do: socket |> Proto.keep_mine(String.to_existing_atom(key)) |> noreply()

  def handle_event(_event, _params, socket) do
    noreply(socket)
  end

  defp page_title(live_resource, :new = _live_action) do
    Backpex.__({"New %{resource}", %{resource: live_resource.singular_name()}}, live_resource)
  end

  defp page_title(live_resource, :edit = _live_action) do
    Backpex.__({"Edit %{resource}", %{resource: live_resource.singular_name()}}, live_resource)
  end

  defp assign_return_to(socket, params) do
    case LiveResource.return_to_param(params) do
      nil -> socket
      return_to -> assign(socket, :return_to, return_to)
    end
  end

  defp assign_item(socket, :new = _live_action) do
    schema = socket.assigns.live_resource.adapter_config(:schema)
    empty_item = schema.__struct__()

    assign(socket, :item, empty_item)
  end

  defp assign_item(socket, :edit = _live_action) do
    %{live_resource: live_resource, fields: fields, params: params} = socket.assigns

    primary_value = Map.fetch!(params, "backpex_id")

    item = Resource.get!(primary_value, fields, socket.assigns, live_resource)

    assign(socket, :item, item)
  end

  defp can?(socket, live_resource, :new = live_action) do
    Authorization.authorize!(live_resource, socket.assigns, live_action, nil)

    socket
  end

  defp can?(socket, live_resource, :edit = live_action) do
    Authorization.authorize!(live_resource, socket.assigns, live_action, socket.assigns.item)

    socket
  end

  defp assign_changeset(socket, live_action) do
    %{live_resource: live_resource, item: item, fields: fields} = socket.assigns

    changeset_fun = changeset_fun(live_resource, live_action)
    LiveResource.assign_changeset(socket, changeset_fun, item, fields, live_action)
  end

  defp changeset_fun(live_resource, :new = _live_action), do: live_resource.adapter_config(:create_changeset)
  defp changeset_fun(live_resource, :edit = _live_action), do: live_resource.adapter_config(:update_changeset)
end
