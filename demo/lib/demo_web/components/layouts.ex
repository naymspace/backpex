defmodule DemoWeb.Layouts do
  @moduledoc false
  use DemoWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :fluid?, :boolean, default: true, doc: "if the content uses full width"
  attr :current_url, :string, required: true, doc: "the current url"

  slot :inner_block, required: true

  def admin(assigns)
end
