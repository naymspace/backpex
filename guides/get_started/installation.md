# Installation

The following guide will help you to install Backpex in your Phoenix application. We will guide you through the installation process and show you how to create a simple resource.

Make sure you meet the [prerequisites](prerequisites.md) before you start the installation.

## Add to list of dependencies

In your `mix.exs`:

```elixir
defp deps do
  [
    ...
    {:backpex, "~> 0.3.1"}
  ]
end
```

See the [hex.pm page](https://hex.pm/packages/backpex) for the latest version.

## Add files to Tailwind content

Backpex uses Tailwind CSS and daisyUI. Make sure to add the Backpex files to your tailwind content in order to include the Backpex styles.

In your `tailwind.config.js`:

```js
..,
content: [
  ...,
  // add this line
  'deps/backpex/**/*.*ex'
]
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
mix phx.gen.schema Blog.Post blog_posts title:string views:integer
mix ecto.migrate
```

These commands will generate a `Post` schema and a migration file. The migration file will create a `blog_posts` table in your database.

You are now prepared to set up the Backpex layout and a LiveResource for the `Post` resource.

## Create layout

Backpex does not ship with a predefined layout by default to give you the freedom to create your own layout. Instead, it provides components that you can use to build your own layout. You can find all Backpex components in the `lib/backpex/components` directory. Layout components are placed in the `lib/backpex/components/layout` directory. To start quickly, Backpex provides an `Backpex.HTML.Layout.app_shell/1` component. You can use this component to add an app shell layout to your application easily.

See the following example that uses the `Backpex.HTML.Layout.app_shell/1` component and some other Backpex Layout components to create a simple layout:

```elixir
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
    layout: {MyAppWeb.Layouts, :admin},
    schema: MyApp.Blog.Post,
    repo: MyApp.Repo,
    update_changeset: &MyApp.Blog.Post.update_changeset/3,
    create_changeset: &MyApp.Blog.Post.create_changeset/3,
    pubsub: MyApp.PubSub,
    topic: "posts",
    event_prefix: "post_",
end
```

`Backpex.LiveResource` is the module that will generate the corresponding LiveViews for the resource you configured. We provide a macro you have to use to configure the LiveResource. You are required to set some general options to tell Backpex where to find the resource and what changesets should be used. The above example shows the configuration for a `Post` resource.

All options you can see in the above example are required:

- The `layout` option tells Backpex which layout to use for the LiveResource. In this case, we use the `:admin`(`admin.html.heex`) layout created in the previous step.
- The `schema` option tells Backpex which schema to use for the resource.
- The `repo` option tells Backpex which repo to use for the resource.
- The `update_changeset` and `create_changeset` options tell Backpex which changesets to use for updating and creating the resource.
- The `pubsub` option tells Backpex which pubsub to use for the resource (see the [Listen to PubSub Events](live_resource/listen-to-pubsub-events.md) guide for more information).
- The `topic` option tells Backpex which topic to use for the resource when broadcasting events.
- The `event_prefix` option tells Backpex which event prefix to use for the resource when broadcasting events.

In addition to the required options, you pass to the `Backpex.LiveResource` macro, you are required to implement the following callback functions in the module:

- [`singular_name/0`](Backpex.LiveResource.html#c:singular_name/0) - This function should return the singular name of the resource.
- [`plural_name/0`](Backpex.LiveResource.html#c:plural_name/0) - This function should return the plural name of the resource.
- [`fields/0`](Backpex.LiveResource.html#c:fields/0) - This function should return a list of fields to display in the LiveResource.

After implementing the required callback functions, our `PostLive` module looks like this:

```elixir
defmodule MyAppWeb.Live.PostLive do
  use Backpex.LiveResource,
    layout: {MyAppWeb.Layouts, :admin},
    schema: MyApp.Blog.Post,
    repo: MyApp.Repo,
    update_changeset: &MyApp.Blog.Post.update_changeset/3,
    create_changeset: &MyApp.Blog.Post.create_changeset/3,
    pubsub: MyApp.PubSub,
    topic: "posts",
    event_prefix: "post_",

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
```

The `fields/0` function returns a list of fields to display in the LiveResource. See [What is a Field?](fields/what-is-a-field.md) for more information.

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

scope "/admin", DemoWeb do
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

scope "/admin", DemoWeb do
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

scope "/admin", DemoWeb do
  pipe_through :browser

  backpex_routes()

  live_session :default, on_mount: Backpex.InitAssigns do
    # add this line
    live_resources "/posts", PostLive
  end
end
```

This macro will add the required routes for the `PostLive` module. You can now access the `PostLive` LiveResource at `/admin/posts`.
