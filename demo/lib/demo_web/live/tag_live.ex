defmodule DemoWeb.TagLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Tag,
      repo: Demo.Repo,
      update_changeset: &Demo.Tag.update_changeset/3,
      create_changeset: &Demo.Tag.create_changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    init_order: %{by: :name, direction: :desc},
    on_mount: __MODULE__

  def on_mount(:default, _params, _session, socket) do
    msg = """
    Hi there, this is a flash from #{inspect(__ENV__.function)}
    in #{__MODULE__} via the #{socket.assigns.live_action} live_action.
    You can do all kind of stuff in here, like attaching hooks to handle_event, handle_info or handle_params.
    """

    {:cont, Phoenix.LiveView.put_flash(socket, :info, msg)}
  end

  @impl Backpex.LiveResource
  def singular_name, do: "Tag"

  @impl Backpex.LiveResource
  def plural_name, do: "Tags"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true,
        placeholder: "Tag name"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Inserted At",
        only: [:show, :index]
      }
    ]
  end

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    Enum.concat(
      [
        duplicate: %{
          module: DemoWeb.ItemActions.DuplicateTag,
          only: [:row]
        }
      ],
      default_actions
    )
  end
end
