# on_mount Hook

Backpex provides a way to add `on_mount` hooks that are invoked on the LiveView's mount (see https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#on_mount/1).

You can use an `on_mount` hook to attach a `handle_event`, `handle_params` or `handle_info` callback to your LiveResource, 
e.g. if you add additional code that sends events to the LiveView and you need to handle them.

## Configuration

Simply set the `on_mount` option in your LiveResource and add a `on_mount` callback.

You can pass a single value or a list of multiple hooks similar to the `on_mount` option
for LiveView's `live_session` function: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Router.html#live_session/3-options.

```elixir
use Backpex.LiveResource,
  ...,
  on_mount: {__MODULE__, :my_hook}

def on_mount(:my_hook, _params, _session, socket) do
  socket = Phoenix.LiveView.attach_hook(socket, :handle_event_callback, :handle_event, &handle_event/3)

  {:cont, socket}
end

def handle_event("my-event", _params_, socket) do
  # Do stuff

  {:halt, socket}
end

def handle_event(_event_, _params_, socket) do
  {:cont, socket}
end
```

**Important:** 
Make sure to halt for custom events as Backpex won't handle them. In addition, you are required to add a catch-all event at the end that continues. 
Otherwise, Backpex will not receive internal events.
