defmodule DemoWeb.Layouts do
  @moduledoc false
  use DemoWeb, :html

  embed_templates "layouts/*"

  attr :socket, :any, required: true, doc: "the socket"
  attr :live_resource, :atom, default: nil, doc: "the LiveResource, nil on pages that are not a LiveResource"
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :fluid?, :boolean, default: true, doc: "if the content uses full width"
  attr :current_url, :string, required: true, doc: "the current url"
  attr :current_theme, :string, default: nil, doc: "the currently selected theme"
  attr :sidebar_open, :boolean, default: true, doc: "initial sidebar open state"
  attr :sidebar_section_states, :map, default: %{}, doc: "open state of the sidebar sections, by section id"

  attr :preferences_manifest, :map,
    default: nil,
    doc: "adapter route manifest for client-carried preference values, assigned by Backpex.InitAssigns"

  slot :inner_block, required: true

  def admin(assigns)
end
