defmodule Backpex.Test.OnMountHook do
  @moduledoc """
  An `on_mount` hook that records that it ran: it appends `"<argument> hook ran on <view>"` to the info flash, which the
  admin layout renders.
  """
  import Phoenix.LiveView, only: [put_flash: 3]

  def on_mount(argument, _params, _session, socket) do
    message = "#{inspect(argument)} hook ran on #{inspect(socket.view)}"

    # The connected mount receives the flash of the disconnected one, so a message is only added once.
    info =
      case Phoenix.Flash.get(socket.assigns.flash, :info) do
        nil -> message
        previous -> if String.contains?(previous, message), do: previous, else: previous <> "; " <> message
      end

    {:cont, put_flash(socket, :info, info)}
  end
end

defmodule Backpex.Test.OnMountModuleNoteLive do
  @moduledoc "Notes with a module as `on_mount` hook."
  use Backpex.Test.OptionsNoteLive, on_mount: Backpex.Test.OnMountHook
end

defmodule Backpex.Test.OnMountTupleNoteLive do
  @moduledoc "Notes with a `{module, argument}` tuple as `on_mount` hook."
  use Backpex.Test.OptionsNoteLive, on_mount: {Backpex.Test.OnMountHook, :tuple}
end

defmodule Backpex.Test.OnMountListNoteLive do
  @moduledoc "Notes with a list of a module and a `{module, argument}` tuple as `on_mount` hooks."
  use Backpex.Test.OptionsNoteLive, on_mount: [Backpex.Test.OnMountHook, {Backpex.Test.OnMountHook, :second}]
end
