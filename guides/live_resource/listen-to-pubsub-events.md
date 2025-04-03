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

### Listen to events

You can listen for Backpex PubSub events by implementing the Phoenix.LiveView [`handle_info/2`](Phoenix.LiveView.html#c:handle_info/2) callback in your *LiveResource* module:

```elixir
# in your resource configuration file

@impl Phoenix.LiveView
def handle_info({"created", item}, socket) do
    # make something in response to the event
    {:noreply, socket}
end

@impl Phoenix.LiveView
def handle_info({"updated", item}, socket) do
    # make something in response to the event
    {:noreply, socket}
end

@impl Phoenix.LiveView
def handle_info({"deleted", item}, socket) do
    # make something in response to the event
    {:noreply, socket}
end
```
