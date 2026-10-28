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
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Note,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Note.changeset/3,
      create_changeset: &Backpex.Test.Note.changeset/3
    ],
    on_mount: Backpex.Test.OnMountHook

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Note"

  @impl Backpex.LiveResource
  def plural_name, do: "Notes"

  @impl Backpex.LiveResource
  def fields, do: [title: %{module: Backpex.Fields.Text, label: "Title"}]
end

defmodule Backpex.Test.OnMountTupleNoteLive do
  @moduledoc "Notes with a `{module, argument}` tuple as `on_mount` hook."
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Note,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Note.changeset/3,
      create_changeset: &Backpex.Test.Note.changeset/3
    ],
    on_mount: {Backpex.Test.OnMountHook, :tuple}

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Note"

  @impl Backpex.LiveResource
  def plural_name, do: "Notes"

  @impl Backpex.LiveResource
  def fields, do: [title: %{module: Backpex.Fields.Text, label: "Title"}]
end

defmodule Backpex.Test.OnMountListNoteLive do
  @moduledoc "Notes with a list of a module and a `{module, argument}` tuple as `on_mount` hooks."
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Note,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Note.changeset/3,
      create_changeset: &Backpex.Test.Note.changeset/3
    ],
    on_mount: [Backpex.Test.OnMountHook, {Backpex.Test.OnMountHook, :second}]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Note"

  @impl Backpex.LiveResource
  def plural_name, do: "Notes"

  @impl Backpex.LiveResource
  def fields, do: [title: %{module: Backpex.Fields.Text, label: "Title"}]
end
