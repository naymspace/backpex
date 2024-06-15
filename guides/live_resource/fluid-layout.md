# Fluid Layout

Backpex provides a way to create a fluid layout. A fluid layout is a layout that fills the entire width of the screen. This layout is useful for applications that need to display a lot of content on the screen.

> #### Information {: .info}
>
> The  `fluid?` options requires you to pass the `fluid?` assign to the `Backpex.HTML.Layout.app_shell/1` component in your layout file. See the [Create layout](get_started/installation.md#create-layout) documentation for more information.

## Configure LiveResource

To create a fluid layout, you need to set the `fluid?` option in a `LiveResource` to `true`. 

```elixir
# in your LiveResource module
defmodule MyAppWeb.Live.UserLive do
  use Backpex.LiveResource, fluid?: true
end
```