defmodule Backpex.Test.Layouts do
  @moduledoc """
  The root and admin layouts of the test app, built from the Backpex layout components like in a generated app.
  """
  use Phoenix.Component

  alias Backpex.HTML.CoreComponents
  alias Backpex.HTML.Layout

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full" data-theme={assigns[:current_theme] || "light"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>{assigns[:page_title] || "Backpex"}</title>
        <link rel="stylesheet" href="/assets/app.css" />
        <script defer type="text/javascript" src="/assets/app.js">
        </script>
      </head>
      <body class="h-full">
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :flash, :map, required: true
  attr :fluid?, :boolean, default: false
  attr :current_url, :string, default: nil
  attr :current_theme, :string, default: nil
  attr :sidebar_open, :boolean, default: true
  attr :sidebar_section_states, :map, default: %{}
  attr :preferences_manifest, :map, default: nil
  attr :socket, :any, required: true
  attr :live_resource, :atom, default: nil
  slot :inner_block, required: true

  def admin(assigns) do
    ~H"""
    <Layout.app_shell
      socket={@socket}
      fluid={@fluid?}
      live_resource={@live_resource}
      sidebar_open={@sidebar_open}
      preferences_manifest={@preferences_manifest}
    >
      <:topbar>
        <div class="flex-1"></div>
        <Layout.theme_selector current_theme={@current_theme} themes={[{"Light", "light"}, {"Dark", "dark"}]} />
      </:topbar>
      <:sidebar_branding>
        <Layout.sidebar_branding />
      </:sidebar_branding>
      <:sidebar>
        <Layout.sidebar_item current_url={@current_url} navigate="/admin/posts">
          <CoreComponents.icon name="hero-book-open" class="size-5" /> Posts
        </Layout.sidebar_item>
        <Layout.sidebar_section id="relations" sidebar_section_states={@sidebar_section_states}>
          <:label>Relations</:label>
          <Layout.sidebar_item current_url={@current_url} navigate="/admin/categories">
            <CoreComponents.icon name="hero-tag" class="size-5" /> Categories
          </Layout.sidebar_item>
          <Layout.sidebar_item current_url={@current_url} navigate="/admin/tags">
            <CoreComponents.icon name="hero-tag" class="size-5" /> Tags
          </Layout.sidebar_item>
        </Layout.sidebar_section>
      </:sidebar>
      <Layout.flash_messages flash={@flash} />
      {render_slot(@inner_block)}
    </Layout.app_shell>
    """
  end
end
