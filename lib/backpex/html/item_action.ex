defmodule Backpex.HTML.ItemAction do
  @moduledoc """
  Item action-specific UI components.
  """
  use BackpexWeb, :html

  alias Backpex.HTML.Layout

  require Backpex

  @doc """
  Renders the item action confirmation modal.

  This modal is displayed when an item action requires confirmation.
  It supports both simple confirmation messages and forms for actions that require additional input.
  """
  attr :action_to_confirm, :map, required: true, doc: "The action to confirm"
  attr :live_resource, :atom, required: true, doc: "The live resource module"

  def action_confirm_modal(assigns) do
    ~H"""
    <Layout.modal
      :if={@action_to_confirm}
      id="action-confirm-modal"
      title={@action_to_confirm.module.label(assigns, nil)}
      on_cancel={JS.push("cancel-action-confirm")}
      close_label={Backpex.__("Close modal", @live_resource)}
      open
    >
      <div class="px-5 py-3">
        {@action_to_confirm.module.confirm(assigns)}
      </div>
      <div>
        <.live_component
          module={Backpex.FormComponent}
          id={:item_action_modal}
          live_resource={@live_resource}
          action_type={:item}
          {Map.drop(assigns, [:socket, :flash, :fields])}
        />
      </div>
    </Layout.modal>
    """
  end
end
