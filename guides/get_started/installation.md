# Installation

The following guide will help you to install Backpex in your Phoenix application. We will guide you through the installation process and show you how to create a simple resource.

## Prerequisites

Backpex integrates seamlessly with your existing Phoenix LiveView application, but there are a few prerequisites you need to meet before you can start using it.

## Global configuration

Set the PubSub server of your application in your `config.exs`:

```elixir
config :backpex, :pubsub_server, MyApp.PubSub
```

See the [Listen to PubSub Events](live_resource/listen-to-pubsub-events.md) guide for more info on how use and customize
your PubSub configuration.

### Phoenix LiveView

Backpex is built on top of Phoenix LiveView, so you need to have Phoenix LiveView installed in your application. If you generate a new Phoenix application using the latest version of the `mix phx.new` generator, Phoenix LiveView is included by default.

### Backpex Hooks

Backpex comes with a few JS hooks which need to be included in your `app.js`.

```javascript
import { Hooks as BackpexHooks } from 'backpex';

const Hooks = [] // your application hooks (optional)

const liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {...Hooks, ...BackpexHooks }
})
```

### Tailwind CSS

Backpex uses Tailwind CSS for styling. Make sure you have Tailwind CSS installed in your application. You can install Tailwind CSS by following the [official installation guide](https://tailwindcss.com/docs/installation/framework-guides/phoenix). If you generate a new Phoenix application using the latest version of the `mix phx.new` generator, Tailwind CSS is included by default.

*Note that the current version of Backpex requires Tailwind CSS version 4*

### daisyUI

Backpex is styled using daisyUI. Make sure you have daisyUI installed in your application. You can install daisyUI by following the [official installation guide](https://daisyui.com/docs/install/).

*Note that the current version of Backpex requires daisyUI version 5.*

### Ecto

Backpex currently depends on Ecto as the database layer. Make sure you have a running Ecto repository in your application.

> #### Warning {: .warning}
>
> Backpex requires a single primary key field in your database schema. Compound keys are not supported. We tested Backpex with UUID (binary_id), integer (bigserial) and string primary keys. Note that the primary key is used in the URL for Show and Edit Views, so make sure it is always URL-encoded or safe to use in a URL.

If you meet all these prerequisites, you are ready to install and configure Backpex in your Phoenix application. See our [installation guide](guides/get_started/installation.md) for more information on how to install and configure Backpex.

## Add to list of dependencies

In your `mix.exs`:

```elixir
defp deps do
  [
    ...
    {:backpex, "~> 0.11.0"}
  ]
end
```

See the [hex.pm page](https://hex.pm/packages/backpex) for the latest version.

## Add files to Tailwind content

Backpex uses Tailwind CSS and daisyUI. Make sure to add Backpex files as a tailwind source in order to include the Backpex styles.

In your stylesheet:

```css
@source "../../deps/backpex/**/*.*ex";
```

> #### Info {: .info}
>
> The path to the Backpex files may vary depending on your project setup.

## Setup formatter

Backpex ships with a formatter configuration. To use it, add Backpex to the list of dependencies in your `.formatter.exs`.

```elixir
# my_app/.formatter.exs
[
  import_deps: [:backpex]
]
```

## Create an example resource

To make it more practical, we are going to create a simple resource that we will use in all our examples later in the installation guide. You can skip this step if you want to use your own resource or just follow the guide.

The example resource will be a `Post` resource with the following fields:

- `title` (string)
- `views` (integer)

Run the following commands:

```bash
$ mix phx.gen.schema Blog.Post blog_posts title:string views:integer
$ mix ecto.migrate
```

These commands will generate a `Post` schema and a migration file. The migration file will create a `blog_posts` table in your database.

You are now prepared to set up the Backpex layout and a LiveResource for the `Post` resource.

## Create layout

Backpex does not ship with a predefined layout by default to give you the freedom to create your own layout. Instead, it provides components that you can use to build your own layout. You can find all Backpex components in the `lib/backpex/components` directory. Layout components are placed in the `lib/backpex/components/layout` directory. To start quickly, Backpex provides an `Backpex.HTML.Layout.app_shell/1` component. You can use this component to add an app shell layout to your application easily.

See the following example that uses the `Backpex.HTML.Layout.app_shell/1` component and some other Backpex Layout components to create a simple layout:

```heex
<Backpex.HTML.Layout.app_shell fluid={@fluid?}>
  <:topbar>
    <Backpex.HTML.Layout.topbar_branding />

    <Backpex.HTML.Layout.topbar_dropdown>
      <:label>
        <label tabindex="0" class="btn btn-square btn-ghost">
          <.icon name="hero-user" class="h-8 w-8" />
        </label>
      </:label>
      <li>
        <.link navigate={~p"/"} class="flex justify-between text-red-600 hover:bg-gray-100">
          <p>Logout</p>
          <.icon name="hero-arrow-right-on-rectangle" class="h-5 w-5" />
        </.link>
      </li>
    </Backpex.HTML.Layout.topbar_dropdown>
  </:topbar>
  <:sidebar>
    <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/posts"}>
      <.icon name="hero-book-open" class="h-5 w-5" /> Posts
    </Backpex.HTML.Layout.sidebar_item>
  </:sidebar>
  <Backpex.HTML.Layout.flash_messages flash={@flash} />
  <%= @inner_content %>
</Backpex.HTML.Layout.app_shell>
```

Make sure to add the `Backpex.HTML.Layout.flash_messages` component to display flash messages in your layout and do not forget to add the `@inner_content` variable to render the content of the LiveView.

Place the layout file in your `lib/myapp_web/templates/layout` directory. You can name it like you want, but we recommend to use `admin.html.heex`. You can also use this layout as the only layout in your application if your application consists of only an admin interface.

We use the `icon/1` component to render icons in the layout. This component is part of the `core_components` module that ships with new Phoenix projects. See [`core_components.ex`](https://github.com/phoenixframework/phoenix/blob/main/priv/templates/phx.gen.live/core_components.ex). Feel free to use your own icon component or library.

> #### Information {: .info}
>
> The `Backpex.HTML.Layout.app_shell/1` component accepts a boolean `fluid` to determine if a `LiveResource` should be rendered full width. There is a `fluid?` option you can configure in a `LiveResource`. See the [Fluid Layout documentation](live_resource/fluid-layout.md) for more information.

## Configure LiveResource

To create a LiveResource for the `Post` resource, you need to create LiveResource module.

```elixir
defmodule MyAppWeb.Live.PostLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: MyApp.Blog.Post,
      repo: MyApp.Repo,
      update_changeset: &MyApp.Blog.Post.update_changeset/3,
      create_changeset: &MyApp.Blog.Post.create_changeset/3
    ],
    layout: {MyAppWeb.Layouts, :admin}
end
```

`Backpex.LiveResource` is the module that will generate the corresponding LiveViews for the resource you configured. We provide a macro you have to use to configure the LiveResource. You are required to set some general options to tell Backpex where to find the resource and what changesets should be used. The above example shows the configuration for a `Post` resource.

All options you can see in the above example are required:

- The `layout` option tells Backpex which layout to use for the LiveResource. In this case, we use the `:admin`(`admin.html.heex`) layout created in the previous step.
- The `schema` option tells Backpex which schema to use for the resource.
- The `repo` option tells Backpex which repo to use for the resource.
- The `update_changeset` and `create_changeset` options tell Backpex which changesets to use for updating and creating the resource.
- The `pubsub` option tells Backpex which pubsub options to use for the resource (see the [Listen to PubSub Events](live_resource/listen-to-pubsub-events.md) guide for more information).

If your primary key is not named "id", you are also required to set the `primary_key` option:

```elixir
use Backpex.LiveResource,
  adapter_config: [
    ...
  ],
  primary_key: :code
```

In addition to the required options, you pass to the `Backpex.LiveResource` macro, you are required to implement the following callback functions in the module:

- [`singular_name/0`](Backpex.LiveResource.html#c:singular_name/0) - This function should return the singular name of the resource.
- [`plural_name/0`](Backpex.LiveResource.html#c:plural_name/0) - This function should return the plural name of the resource.
- [`fields/0`](Backpex.LiveResource.html#c:fields/0) - This function should return a list of fields to display in the LiveResource.

After implementing the required callback functions, our `PostLive` module looks like this:

```elixir
defmodule MyAppWeb.Live.PostLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: MyApp.Blog.Post,
      repo: MyApp.Repo,
      update_changeset: &MyApp.Blog.Post.update_changeset/3,
      create_changeset: &MyApp.Blog.Post.create_changeset/3
    ],
    layout: {MyAppWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Post"

  @impl Backpex.LiveResource
  def plural_name, do: "Posts"

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{
        module: Backpex.Fields.Text,
        label: "Title"
      },
      views: %{
        module: Backpex.Fields.Number,
        label: "Views"
      }
    ]
  end
end
```

The `fields/0` function returns a list of fields to display in the LiveResource. See [What is a Field?](../fields/what-is-a-field.md) for more information.

> #### Information {: .info}
>
> We recommend placing the *LiveResource* in the `lib/myapp_web/live` directory. You can name the module like you want, but in this case, we recommend using `post_live.ex`.

## Configure Routing

To make the LiveResource accessible in your application, you first need to configure your router (`router.ex`).

### Add Backpex Routes

Backpex needs to add a `backpex_cookies` route to your router. This route is used to set the cookies needed for the Backpex LiveResource.

Backpex provides a macro you can use to add the required routes to your router. Make sure to import `Backpex.Router` at the top of your router file or prefix the function calls.#

You have to do this step only once in your router file, so if you already added the [`backpex_routes/0`](Backpex.Router.html#backpex_routes/0) macro, you can skip this step.

```elixir
# router.ex

import Backpex.Router

scope "/admin", MyAppWeb do
  pipe_through :browser

  # add this line
  backpex_routes()
end
```

It does not matter where you place the [`backpex_routes/0`](Backpex.Router.html#backpex_routes/0) macro in your router file. You can insert it in every scope you want to, but we recommend placing it in the scope you want to use backpex in, e.g. `/admin`.

## Add Init Assigns and LiveSession

Backpex provides a `Backpex.InitAssigns` module. This will attach the `current_url` to the LiveView. Backpex needs it to highlight the current sidebar item in the layout. You can also use your own init assigns module if you want to attach more assigns to the LiveView, but make sure to add the `current_url` to the assigns.

We use a live session to add the init assigns to all LiveViews in the `/admin` scope.

```elixir
# router.ex

import Backpex.Router

scope "/admin", MyAppWeb do
  pipe_through :browser

  backpex_routes()

  # add this line
  live_session :default, on_mount: Backpex.InitAssigns do
  end
end
```

### Add LiveResource routes

To make the LiveResource accessible in your application, you need to add routes for it. Backpex makes it easy to add the required routes to your router by providing the [`live_resources/3`](Backpex.Router.html#live_resources/3) macro.

```elixir
# router.ex

import Backpex.Router

scope "/admin", MyAppWeb do
  pipe_through :browser

  backpex_routes()

  live_session :default, on_mount: Backpex.InitAssigns do
    # add this line
    live_resources "/posts", PostLive
  end
end
```

This macro will add the required routes for the `PostLive` module. You can now access the `PostLive` LiveResource at `/admin/posts`.

### Configure a default route

To make a default route for `/admin` we recommend creating a redirect controller such as the following:

In `my_app_web/controller` create a file named `redirect_controller.ex`:

```elixir
# redirect_controller.ex

defmodule MyAppWeb.RedirectController do
  use MyAppWeb, :controller

  def redirect_to_posts(conn, _params) do
    conn
    |> Phoenix.Controller.redirect(to: ~p"/admin/posts")
    |> Plug.Conn.halt()
  end
end
```

And configure in your `router.ex` file:

```elixir
#router.ex

scope "/admin", MyAppWeb do

  pipe_through :browser

  backpex_routes()

  # add this line
  get "/", RedirectController, :redirect_to_posts

  live_session :default, on_mount: Backpex.InitAssigns do
    live_resources "/posts", PostLive
  end
end
```

## Remove default background color

If you start with a new Phoenix project, you may have a default background color set for your body tag. This conflicts with the background color of the Backpex `app_shell`.

So if you have this in your `root.html.heex`.

```html
<body class="bg-white">
</body>
```

You should remove the `bg-white` class.

If you need this color on your body tag to style your application, consider using another root layout for Backpex (see [`put_root_layout/2`](https://hexdocs.pm/phoenix/Phoenix.Controller.html#put_root_layout/2)).

## Set daisyUI theme

Backpex supports daisyUI themes. The following steps will guide you through setting up daisyUI themes in your application and optionally adding a theme selector to your layout.

**1. Add the themes to your application.**

First, you need to add the themes to your stylesheet. You can add the themes to the `daisyui` plugin options. The following example shows how to add the `light`, `dark`, and `cyberpunk` themes to your application.

```css
@plugin "daisyui" {
  themes: dark, cyberpunk;
}

@plugin "daisyui/theme" {
  name: "light";

  --color-primary: #1d4ed8;
  --color-primary-content: white;
  --color-secondary: #f39325;
  --color-secondary-content: white;
}
```

The full list of themes can be found at the [daisyUI website](https://daisyui.com/docs/themes/).

**2. Set the assign and the default daisyUI theme in your layout.**

We fetch the theme from the assigns and set the `data-theme` attribute on the `html` tag. If no theme is set, we default to the `light` theme.

```heex
# root.html.heex
<html data-theme={assigns[:theme] || "light"}>
  ...
</html>
```

If you just want to use a single theme, you can set the `data-theme` attribute to the theme name. You can skip the next steps and are done with the theme setup.

```heex
# root.html.heex
<html data-theme="light">
  ...
</html>
```

**3. Add `Backpex.ThemeSelectorPlug` to the pipeline in the router**

To add the saved theme to the assigns, you can add the `Backpex.ThemeSelectorPlug` to the pipeline in your router. This plug will fetch the selected theme from the session and put it in the assigns.

```elixir
# router.ex
  pipeline :browser do
    ...
    # Add this plug
    plug Backpex.ThemeSelectorPlug
  end
```

**4. Add the theme selector component to the app shell**

You can add a theme selector to your layout to allow users to change the theme. The following example shows how to add a theme selector to the `admin.html.heex` layout. The list of themes should match the themes you added to your stylesheet.

```heex
# admin.html.heex
<Backpex.HTML.Layout.app_shell fluid={@fluid?}>
  <:topbar>
    <Backpex.HTML.Layout.topbar_branding />
    # Add this
    <Backpex.HTML.Layout.theme_selector
      socket={@socket}
      themes={[
        {"Light", "light"},
        {"Dark", "dark"},
        {"Cyberpunk", "cyberpunk"}
      ]}
    />
    <Backpex.HTML.Layout.topbar_dropdown>
      <:label>
        <label tabindex="0" class="btn btn-square btn-ghost">
          <.icon name="hero-user" class="h-8 w-8" />
        </label>
      </:label>
      <li>
        <.link navigate={~p"/"} class="flex justify-between text-red-600 hover:bg-gray-100">
          <p>Logout</p>
          <.icon name="hero-arrow-right-on-rectangle" class="h-5 w-5" />
        </.link>
      </li>
    </Backpex.HTML.Layout.topbar_dropdown>
  </:topbar>
  <:sidebar>
    <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/posts"}>
      <.icon name="hero-book-open" class="h-5 w-5" /> Posts
    </Backpex.HTML.Layout.sidebar_item>
  </:sidebar>
  <Backpex.HTML.Layout.flash_messages flash={@flash} />
  <%= @inner_content %>
</Backpex.HTML.Layout.app_shell>
```

**5. Set selected theme**

To set the selected theme as soon as possible, you can run this function inside your `app.js`:

```javascript
import { Hooks as BackpexHooks } from 'backpex';
// ...
BackpexHooks.BackpexThemeSelector.setStoredTheme()
```

This will minimize flashes with the old theme in some situations.

## Remove `@tailwindcss/forms` plugin

There is a conflict between the `@tailwindcss/forms` plugin and daisyUI. You should remove the `@tailwindcss/forms` plugin to prevent styling issues.

```css
// remove this line
@plugin "tailwindcss/forms;
```

If your application depends on the `@tailwindcss/forms` plugin, you can keep the plugin and [change the strategy to `'class'`](https://github.com/tailwindlabs/tailwindcss-forms?tab=readme-ov-file#using-only-global-styles-or-only-classes). This will prevent the plugin from conflicting with daisyUI. Note that you then have to add the form classes provided by the `@tailwindcss/forms` plugin to your inputs manually.

## Provide Tailwind Plugin for heroicons

Backpex uses the [heroicons](https://heroicons.com/) icon set. Backpex provides a `Backpex.HTML.CoreComponents.icon/1` component, but you need to provide the icons and a Tailwind CSS plugin to generate the necessary styles to display them. If you generated your Phoenix project with the latest version of the `mix phx.new` generator, you already have the dependency and plugin installed. If not, follow the steps below.

### Track the heroicons GitHub repository

Track the heroicons GitHub repository with Mix:

```elixir
def deps do
  [
    ...
    {:heroicons,
      github: "tailwindlabs/heroicons",
      tag: "v2.1.1",
      sparse: "optimized",
      app: false,
      compile: false,
      depth: 1}
  ]
end
```

This will add the heroicons repository as a dependency to your project. You can find the optimized SVG icons in the `deps/heroicons` directory.

### Add the Tailwind CSS plugin

Define the following plugin and import it into your stylesheet to generate the necessary styles to display the icons.

```javascript
// tailwind.heroicons.js

// add fs, plugin and path to the top of the file
const plugin = require('tailwindcss/plugin')
const fs = require('fs')
const path = require('path')

module.exports = plugin(function ({ matchComponents, theme }) {
  const iconsDir = path.join(__dirname, '../../deps/heroicons/optimized')
  const values = {}
  const icons = [
    ['', '/24/outline'],
    ['-solid', '/24/solid'],
    ['-mini', '/20/solid'],
    ['-micro', '/16/solid']
  ]
  icons.forEach(([suffix, dir]) => {
    fs.readdirSync(path.join(iconsDir, dir)).forEach((file) => {
      const name = path.basename(file, '.svg') + suffix
      values[name] = { name, fullPath: path.join(iconsDir, dir, file) }
    })
  })
  matchComponents(
    {
      hero: ({ name, fullPath }) => {
        let content = fs
          .readFileSync(fullPath)
          .toString()
          .replace(/\r?\n|\r/g, '')
        content = encodeURIComponent(content)
        let size = theme('spacing.6')
        if (name.endsWith('-mini')) {
          size = theme('spacing.5')
        } else if (name.endsWith('-micro')) {
          size = theme('spacing.4')
        }
        return {
          [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
          '-webkit-mask': `var(--hero-${name})`,
          mask: `var(--hero-${name})`,
          'mask-repeat': 'no-repeat',
          'background-color': 'currentColor',
          'vertical-align': 'middle',
          display: 'inline-block',
          width: size,
          height: size
        }
      }
    },
    { values }
  )
})
```

```css
@plugin "./tailwind_heroicons.js";
```

This plugin will generate the necessary styles to display the heroicons in your application. You can now use the `Backpex.HTML.CoreComponents.icon/1` component to render the icons in your application.

For example, to render the `user` icon, you can use the following code:

```heex
<Backpex.HTML.CoreComponents.icon name="hero-user" class="h-5 w-5" />
```
