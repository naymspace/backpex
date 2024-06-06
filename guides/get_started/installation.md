# Installation

## Prerequisites

Make sure you have a running phoenix application with [Tailwind CSS](https://tailwindcss.com/) and [daisyUI](https://daisyui.com/docs/install/) installed.

> #### Important {: .info}
>
> Backpex currently only supports daisyUI light mode.

Backpex currently depends on [Ecto](https://hexdocs.pm/ecto/Ecto.html). Therefore there has to be a running
ecto repository.

## Add Backpex to list of dependencies

In your `mix.exs`:

```elixir
defp deps do
  [
    ...
    {:backpex, path: "backpex_path"}
  ]
end
```

## Add Backpex files to tailwind content

In your `tailwind.config.js`:

```js
content: ['./path_to_deps/backpex/**/*.*ex']
```

## Setup formatter

We recommend to add Backpex to the list of dependencies in your `.formatter.exs`.

```elixir
# my_app/.formatter.exs
[
  import_deps: [:backpex]
]
```

## Create layout

Backpex does not ship a predefined layout by default. Instead it exposes components you
may use to build your own layout. You could also partly use Backpex components. For example
you are able to define your own sidebar navigation in our app shell component.

Place the layout file in your `lib/myapp_web/templates/layout` directory.

You can find all Backpex components in the `lib/backpex/components` directory.

If you do not want to put effort into creating your own layout, feel free to use this layout (`admin.html.heex`) as a starting point:

> The `Backpex.HTML.Layout.app_shell` component accepts a boolean `fluid` to determine if a `LiveResource` should be rendered full width. Our default is the definition of the `fluid?` option in a `LiveResource`, but feel free to change this behavior in your layout.

```elixir
<Backpex.HTML.Layout.app_shell fluid={@fluid?}>
  <:topbar>
    <Backpex.HTML.Layout.topbar_branding />
    <Backpex.HTML.Layout.topbar_dropdown class="rounded-md p-1 hover:bg-gray-100">
      <:label>
        <Heroicons.user class="h-8 w-8" />
      </:label>
      <div class="py-1">
        <.link navigate="/" class="my-1 flex justify-between px-4 py-2 text-sm text-red-600 hover:bg-gray-100">
          <p>Logout</p>
          <Heroicons.arrow_right_on_rectangle class="h-5 w-5" />
        </.link>
      </div>
    </Backpex.HTML.Layout.topbar_dropdown>
  </:topbar>
  <:sidebar>
    <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate="/">
      <Heroicons.user class="h-5 w-5" /> Your Resource
    </Backpex.HTML.Layout.sidebar_item>
    <Backpex.HTML.Layout.sidebar_section id="your_section">
      <:label>Your Sidebar Section</:label>
      <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate="/">
        <Heroicons.book_open class="h-5 w-5" /> Your nested Resource
      </Backpex.HTML.Layout.sidebar_item>
    </Backpex.HTML.Layout.sidebar_section>
  </:sidebar>
  <Backpex.HTML.Layout.flash_messages flash={@flash} />
  <%= @inner_content %>
</Backpex.HTML.Layout.app_shell>
```

You can now create and configure the corresponding resources.
