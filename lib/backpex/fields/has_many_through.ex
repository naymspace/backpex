defmodule Backpex.Fields.HasManyThrough do
  @config_schema [
    display_field: [
      doc: "The field of the relation to be used for displaying options in the select.",
      type: :atom,
      required: true
    ],
    live_resource: [
      doc: """
      The corresponding live resource of the association. Used to display the title of the modal and generate defaults
      for `:child_fields` fields.
      """,
      type: :atom,
      required: true
    ],
    sort_by: [
      doc: """
      A list of columns by which the child element output will be sorted. The sorting takes place in ascending order.
      """,
      type: {:list, :atom}
    ],
    child_fields: [
      doc: "WIP",
      type: :keyword_list
    ],
    pivot_fields: [
      doc: "List to map additional data of the pivot table to Backpex fields.",
      type: :keyword_list
    ],
    options_query: [
      doc: """
      Manipulates the list of available options in the select. Can be used to select additional data for the `display_field` option or to limit the available entries.",

      Defaults to `fn (query, _field) -> query end` which returns all entries.
      """,
      type: {:fun, 2}
    ]
  ]

  @moduledoc """
  A field for handling a `has_many` (`through`) relation.

  This field is not orderable or searchable.

  > #### Warning {: .warning}
  >
  > This field is in beta state. Use at your own risk.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
      [
        addresses: %{
          module: Backpex.Fields.HasManyThrough,
          label: "Addresses",
          display_field: :street,
          live_resource: DemoWeb.AddressLive,
          sort_by: [:zip, :city],
          pivot_fields: [
            type: %{
              module: Backpex.Fields.Select,
              label: "Address Type",
              options: [Shipping: "shipping", Billing: "billing"]
            }
          ]
        }
      ]
      end

  The field requires a [`Ecto.Schema.has_many/3`](https://hexdocs.pm/ecto/Ecto.Schema.html#has_many/3) relation with a mandatory `through` option in the main schema. Any extra column in the pivot table besides the relational id's must be mapped in the `pivot_fields` option or given a default value.
  """
  use Backpex.Field, config_schema: @config_schema
  import Ecto.Query
  import Backpex.HTML.Layout, only: [modal: 1]
  import PhoenixHTMLHelpers.Form, only: [hidden_inputs_for: 1]
  alias Backpex.LiveResource
  alias Ecto.Changeset

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> apply_action(assigns.type)

    {:ok, socket}
  end

  defp apply_action(socket, :form) do
    %{schema: schema, name: name} = socket.assigns

    association = association(schema, name)

    socket
    |> assign_new(:edit_relational, fn -> nil end)
    |> assign_new(:association, fn -> association end)
    |> assign_options()
  end

  defp apply_action(socket, _type), do: socket

  defp assign_options(%{assigns: %{options: _options, items: _items}} = socket), do: socket

  defp assign_options(socket) do
    %{assigns: %{repo: repo, field_options: field_options, association: association} = assigns} = socket

    display_field = Map.get(field_options, :display_field_form, Map.get(field_options, :display_field))

    all_items =
      from(association.child.queryable)
      |> maybe_options_query(field_options, assigns)
      |> repo.all()

    options = Enum.map(all_items, &{Map.get(&1, display_field), Map.get(&1, :id)})

    prompt =
      {Backpex.translate({"Choose %{resource} ...", %{resource: field_options.live_resource.singular_name()}}), nil}

    socket
    |> assign(:all_items, all_items)
    |> assign(:options, [prompt | options])
  end

  @impl Backpex.Field
  def render_value(assigns) do
    %{item: item, name: assoc_field_name, schema: schema} = assigns

    %{pivot: %{field: pivot_field}, child: %{field: child_field}} = association(schema, assoc_field_name)

    listables =
      Map.get(item, pivot_field, [])
      |> Enum.map(fn listable ->
        %{
          child: Map.get(listable, child_field),
          pivot: listable
        }
      end)
      |> maybe_sort_by(assigns)

    assigns =
      assigns
      |> assign(listables: listables)
      |> assign_fallback_child_fields()

    ~H"""
    <div class="ring-base-content/10 rounded-box overflow-x-auto ring-1">
      <table class="table">
        <thead class="bg-base-200/50 text-base-content uppercase">
          <tr>
            <th
              :for={{_name, %{label: label}} <- action_fields(@field_options.child_fields, assigns, :index)}
              class="font-medium"
            >
              <%= label %>
            </th>
            <th
              :for={{_name, %{label: label}} <- action_fields(@field_options.pivot_fields, assigns, :index)}
              class="font-medium"
            >
              <%= label %>
            </th>
            <th></th>
          </tr>
        </thead>
        <tbody class="text-base-content/75">
          <tr :for={{listable, index} <- Enum.with_index(@listables)}>
            <td :for={{name, field_options} = field <- action_fields(@field_options.child_fields, assigns, :index)}>
              <.live_component
                id={"child_table_#{name}_#{index}"}
                module={field_options.module}
                name={name}
                field_options={field_options}
                field={field}
                value={Map.get(listable.child, name)}
                type={:index}
                {assigns}
              />
            </td>
            <td :for={{name, field_options} = field <- action_fields(@field_options.pivot_fields, assigns, :index)}>
              <.live_component
                id={"pivot_table_#{name}_#{index}"}
                module={field_options.module}
                name={name}
                field_options={field_options}
                field={field}
                value={Map.get(listable.pivot, name)}
                type={:index}
                {assigns}
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    %{field: assoc_field} = assigns = assign_fallback_child_fields(assigns)
    %{form: form, changeset: changeset, association: association, all_items: all_items} = assigns
    {_assoc_field_name, assoc_field_options} = assoc_field
    primary_key = assoc_field_options.live_resource.config(:primary_key)
    editables = editables(form, changeset, association, primary_key)

    listables =
      editables
      |> Enum.map(fn editable ->
        edited = Changeset.apply_changes(editable.source)
        relational_id = Map.get(edited, association.child.owner_key)
        item = Enum.filter(all_items, &(Map.get(&1, primary_key) == relational_id)) |> List.first()
        item = if is_nil(item), do: %{}, else: item

        %{
          index: editable.index,
          pivot: Map.take(edited, Enum.map(assoc_field_options.pivot_fields, fn {name, _field_options} -> name end)),
          child: Map.take(item, Enum.map(assoc_field_options.child_fields, fn {name, _field_options} -> name end))
        }
      end)
      |> maybe_sort_by(assigns)

    relational_title =
      Backpex.translate({"Attach %{resource}", %{resource: assoc_field_options.live_resource.singular_name()}})

    assigns =
      assigns
      |> assign(editables: editables)
      |> assign(listables: listables)
      |> assign(owner_key: association.child.owner_key)
      |> assign(relational_title: relational_title)
      |> assign(association: association)

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>

        <div :if={@listables != []} class="ring-base-content/10 rounded-box mb-4 overflow-x-auto ring-1">
          <table class="table">
            <thead class="bg-base-200/50 text-base-content uppercase">
              <tr>
                <th
                  :for={{_name, %{label: label}} <- action_fields(@field_options.child_fields, assigns, :index)}
                  class="font-medium"
                >
                  <%= label %>
                </th>
                <th
                  :for={{_name, %{label: label}} <- action_fields(@field_options.pivot_fields, assigns, :index)}
                  class="font-medium"
                >
                  <%= label %>
                </th>
                <th></th>
              </tr>
            </thead>
            <tbody class="text-base-content/90">
              <tr
                :for={{listable, index} <- Enum.with_index(@listables)}
                class="border-b-[1px] border-base-content/10 last:border-b-0"
              >
                <td :for={{name, field_options} <- action_fields(@field_options.child_fields, assigns, :index)}>
                  <.live_component
                    id={"child_table_#{name}_#{index}"}
                    module={field_options.module}
                    field_options={field_options}
                    value={Map.get(listable.child, name)}
                    type={:index}
                    {assigns}
                  />
                </td>
                <td :for={{name, field_options} <- action_fields(@field_options.pivot_fields, assigns, :index)}>
                  <.live_component
                    id={"pivot_table_#{name}_#{index}"}
                    module={field_options.module}
                    field_options={field_options}
                    value={Map.get(listable.pivot, name)}
                    type={:index}
                    {assigns}
                  />
                </td>
                <td>
                  <div class="flex items-center space-x-2">
                    <button
                      type="button"
                      phx-click="edit-relational"
                      phx-target={@myself}
                      phx-value-index={listable.index}
                      aria-label={Backpex.translate({"Edit relation with index %{index}", %{index: listable.index}})}
                    >
                      <Backpex.HTML.CoreComponents.icon name="hero-pencil-square" class="h-5 w-5" />
                    </button>
                    <button
                      type="button"
                      phx-click="detach-relational"
                      phx-target={@myself}
                      phx-value-index={listable.index}
                      aria-label={Backpex.translate({"Detach relation with index %{index}", %{index: listable.index}})}
                    >
                      <Backpex.HTML.CoreComponents.icon name="hero-trash" class="h-5 w-5" />
                    </button>
                    <div
                      :if={has_error?(@editables, index)}
                      aria-label={Backpex.translate({"Error in relation with index %{index}", %{index: listable.index}})}
                    >
                      <Backpex.HTML.CoreComponents.icon name="hero-exclamation-triangle" class="text-error h-5 w-5" />
                    </div>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.modal
          open={@edit_relational != nil}
          title={@relational_title}
          close_event_name="cancel-relational"
          target={@myself}
          max_width="xl"
        >
          <div class="py-3">
            <div :for={e <- @editables} class={[unless(e.index == @edit_relational, do: "hidden")]}>
              <%= hidden_inputs_for(e) %>
              <.select_relational_field
                form={e}
                label={@field_options.live_resource.singular_name()}
                field_options={@field}
                owner_key={@owner_key}
                options={@options}
              />
              <.pivot_field :for={{name, _field_options} <- @field_options.pivot_fields} name={name} form={e} {assigns} />
            </div>
          </div>
          <div class="bg-base-200 flex justify-end space-x-4 px-6 py-3">
            <button type="button" class="btn" phx-click="cancel-relational" phx-target={@myself}>
              <%= Backpex.translate("Cancel") %>
            </button>

            <button type="button" class="btn btn-primary" phx-click="complete-relational" phx-target={@myself}>
              <%= Backpex.translate("Apply") %>
            </button>
          </div>
        </.modal>

        <button type="button" class="btn btn-sm btn-outline btn-primary" phx-click="new-relational" phx-target={@myself}>
          <%= @relational_title %>
        </button>
      </Layout.field_container>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("new-relational", _params, socket) do
    %{changeset: changeset, association: association} = socket.assigns

    existing = get_change_or_field(changeset, association.pivot.field)
    all_assocs = Enum.concat(existing, [%{}])
    change = Changeset.get_change(changeset, association.pivot.field, existing)

    put_assoc(association.pivot.field, all_assocs)

    socket =
      socket
      |> assign(return_to_change: change)
      |> assign(edit_relational: Enum.count(existing))

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("detach-relational", %{"index" => index}, socket) do
    %{changeset: changeset, association: association, field_options: field_options} = socket.assigns

    index = String.to_integer(index)
    existing = get_change_or_field(changeset, association.pivot.field)
    {to_delete, rest} = List.pop_at(existing, index)

    primary_key = field_options.live_resource.config(:primary_key)

    updated =
      if Changeset.change(to_delete).data |> Map.get(primary_key) == nil do
        rest
      else
        # mark item for deletion in changeset
        List.replace_at(
          existing,
          index,
          %{Changeset.change(to_delete) | action: :delete}
        )
      end

    put_assoc(association.pivot.field, updated)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("edit-relational", %{"index" => index}, socket) do
    %{changeset: changeset, association: association} = socket.assigns

    existing = get_change_or_field(changeset, association.pivot.field)
    index = String.to_integer(index)
    change = Changeset.get_change(changeset, association.pivot.field, existing)

    socket =
      socket
      |> assign(edit_relational: index)
      |> assign(return_to_change: change)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("complete-relational", _params, socket) do
    socket =
      socket
      |> assign(edit_relational: nil)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("cancel-relational", _params, socket) do
    %{association: association, return_to_change: return_to_change} = socket.assigns

    put_assoc(association.pivot.field, return_to_change)

    socket =
      socket
      |> assign(edit_relational: nil)

    {:noreply, socket}
  end

  defp action_fields(fields, assigns, action), do: LiveResource.filtered_fields_by_action(fields, assigns, action)

  defp assign_fallback_child_fields(assigns) do
    case Map.has_key?(assigns.field_options, :child_fields) do
      true ->
        assigns

      false ->
        fields = assigns.field_options.live_resource.validated_fields()
        new_field_options = Map.put(assigns.field_options, :child_fields, fields)

        assigns
        |> assign(:field, {assigns.name, new_field_options})
        |> assign(:field_options, new_field_options)
    end
  end

  defp has_error?(editables, index) do
    editables
    |> Enum.at(index)
    |> Map.get(:errors, [])
    |> Enum.count()
    |> Kernel.>(0)
  end

  @impl Backpex.Field
  def association?(_field), do: true

  defp pivot_field(assigns) do
    name = assigns.name

    field_options =
      assigns.field_options.pivot_fields
      |> Keyword.get(name)

    assigns =
      assigns
      |> assign(:name, name)
      |> assign(:field_options, field_options)

    ~H"""
    <.live_component
      id={"pivot_modal_#{@name}_#{@form.index}"}
      module={@field_options.module}
      field_uploads={get_in(assigns, [:uploads, @name])}
      type={:form}
      {assigns}
    />
    """
  end

  defp put_assoc(key, value) do
    send(self(), {:put_assoc, {key, value}})
  end

  defp get_change_or_field(changeset, key) do
    with nil <- Changeset.get_change(changeset, key) do
      Changeset.get_field(changeset, key, [])
    end
  end

  defp maybe_options_query(query, %{options_query: options_query} = _field_options, assigns),
    do: options_query.(query, assigns)

  defp maybe_options_query(query, _field_options, _assigns), do: query

  defp association(parent_schema, field_name) do
    assoc = parent_schema.__schema__(:association, field_name)
    pivot = parent_schema.__schema__(:association, List.first(assoc.through))
    child = pivot.queryable.__schema__(:association, List.last(assoc.through))

    %{
      pivot: %{
        field: pivot.field,
        queryable: pivot.queryable,
        owner_key: child.owner_key
      },
      child: %{
        field: child.field,
        queryable: child.queryable,
        owner_key: child.owner_key
      }
    }
  end

  defp editables(form, changeset, association, primary_key) do
    deleted_ids =
      case Changeset.get_change(changeset, association.pivot.field) do
        nil ->
          []

        changes ->
          Enum.filter(changes, &(&1.action == :delete))
          |> Enum.map(&Map.get(&1.data, primary_key))
      end

    form.impl.to_form(form.source, form, association.pivot.field, [])
    |> Enum.filter(fn item ->
      !Enum.member?(deleted_ids, Map.get(item.data, primary_key))
    end)
  end

  defp maybe_sort_by(
         [%{child: _child} | _tail] = items,
         %{field: %{sort_by: column_names}} = _assigns
       ) do
    items
    |> Enum.sort_by(fn item ->
      column_names
      |> Enum.map(&{&1, Map.get(item.child, &1)})
      |> Keyword.values()
      |> Enum.join()
    end)
  end

  defp maybe_sort_by(items, _assigns) do
    items
  end

  defp select_relational_field(assigns) do
    ~H"""
    <Layout.field_container>
      <:label>
        <Layout.input_label text={@label} />
      </:label>
      <BackpexForm.input
        type="select"
        field={@form[@owner_key]}
        options={@options}
        translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
        phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
        phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
      />
    </Layout.field_container>
    """
  end
end
