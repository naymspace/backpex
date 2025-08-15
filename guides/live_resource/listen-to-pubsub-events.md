# Listen to PubSub Events

As mentioned in the [installation guide](get_started/installation.md) you are able to configure PubSub events for each
*LiveResources* individually. Backpex will use the configuration to publish `deleted`, `updated` and `created` events.
Backpex will listen to these events and update the UI accordingly. Sometimes you may want to listen to these events and 
perform some custom actions. For example you want to show a toast to all users currently on the resource that a post has
been created.

### Customize Configuration

You may overwrite the PubSub configuration for your Posts *LiveResource* like this:

```elixir
use Backpex.LiveResource,
  ...,
  pubsub: [
    server: Demo.PubSub
    topic: "posts"
  ]
```

If you do not set a topic yourself, we take the stringified version of the live resource name as the default topic.

```elixir
iex(1)> to_string(DemoWeb.UserLive)
"Elixir.DemoWeb.UserLive"
```

The server can be configured in your `config.exs`:

```elixir
config :backpex, pubsub_server: Demo.PubSub,
```

### Listen to events

You can listen for Backpex PubSub events by implementing the Phoenix.LiveView [`handle_info/2`](Phoenix.LiveView.html#c:handle_info/2) callback in your *LiveResource* module. You can attach this callback via an [`on_mount` hook](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#on_mount/1) by setting the `on_mount` option in your LiveResource.

```elixir
# in your resource configuration file
use Backpex.LiveResource,
  on_mount: __MODULE__,
  ...

  def on_mount(:default, _params, _session, socket) do
    socket = Phoenix.LiveView.attach_hook(socket, :handle_pubsub_messages, :handle_info, &handle_info/2)
    {:cont, socket}
  end

  def handle_info({"created", item}, socket) do
    # make something in response to the event
    {:halt, socket}
  end

  def handle_info({"updated", item}, socket) do
    # make something in response to the event
    {:halt, socket}
  end

  def handle_info({"deleted", item}, socket) do
    # make something in response to the event
    {:halt, socket}
  end

  ...
end
```
