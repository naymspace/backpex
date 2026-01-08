defmodule DemoWeb.Layouts do
  @moduledoc false
  use DemoWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :fluid?, :boolean, default: true, doc: "if the content uses full width"
  attr :current_url, :string, required: true, doc: "the current url"
  attr :current_theme, :string, default: nil, doc: "the currently selected theme"
  attr :sidebar_open, :boolean, default: true, doc: "initial sidebar open state"

  slot :inner_block, required: true

  def admin(assigns)
end
