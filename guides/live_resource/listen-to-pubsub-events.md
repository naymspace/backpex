# Listen to PubSub Events

As mentioned in the [installation guide](get_started/installation.md) you need to configure PubSub for your *LiveResources*. Backpex will use the configuration to publish `deleted`, `updated` and `created` events. Backpex will listen to these events and update the UI accordingly. Sometimes you may want to listen to these events and perform some custom actions. For example you want to show a toast to all users currently on the resource that a post has been created.

### Configuration

You can listen for Backpex PubSub events by implementing the Phoenix.LiveView [`handle_info/2`](Phoenix.LiveView.html#c:handle_info/2) callback in your *LiveResource* module.

We assume you configured PubSub for your Posts *LiveResource* like this:

```elixir
use Backpex.LiveResource,
    ...,
    pubsub: Demo.PubSub
    topic: "posts",
    event_prefix: "post_"
```

You could implement the following `handle_info/2` callbacks in your *LiveResource*:

```elixir
# in your resource configuration file

@impl Phoenix.LiveView
def handle_info({"post_created", item}, socket) do
    # make something in response to the event
    {:noreply, socket}
end

@impl Phoenix.LiveView
def handle_info({"post_updated", item}, socket) do
    # make something in response to the event
    {:noreply, socket}
end

@impl Phoenix.LiveView
def handle_info({"post_deleted", item}, socket) do
    # make something in response to the event
    {:noreply, socket}
end
```
