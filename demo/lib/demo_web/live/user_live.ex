defmodule DemoWeb.UserLive do
  use Backpex.LiveResource,
    layout: {DemoWeb.Layouts, :admin},
    schema: Demo.User,
    repo: Demo.Repo,
    update_changeset: &Demo.User.changeset/3,
    create_changeset: &Demo.User.changeset/3,
    pubsub: Demo.PubSub,
    topic: "users",
    event_prefix: "user_"

  alias Demo.Repo
  alias Demo.User

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def can?(_assigns, :soft_delete, item), do: item.role != :admin

  @impl Backpex.LiveResource
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def item_query(query, live_action, _assigns) when live_action in [:index, :resource_action] do
    from u in query,
      where: is_nil(u.deleted_at)
  end

  @impl Backpex.LiveResource
  def resource_actions do
    [
      invite: %{module: DemoWeb.ResourceActions.Email},
      upload: %{module: DemoWeb.ResourceActions.Upload}
    ]
  end

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    default_actions
    |> Keyword.drop([:delete])
    |> Enum.concat(soft_delete: %{module: DemoWeb.ItemActions.SoftDelete})
  end

  @impl Backpex.LiveResource
  def panels do
    [names: "Names"]
  end

  @impl Backpex.LiveResource
  def fields do
    [
      avatar: %{
        module: Backpex.Fields.Upload,
        label: "Avatar",
        upload_key: :avatar,
        accept: ~w(.jpg .jpeg),
        max_entries: 1,
        max_file_size: 512_000,
        put_upload_change: &put_upload_change/6,
        consume_upload: &consume_upload/3,
        remove_uploads: &remove_uploads/2,
        list_existing_files: fn
          %{avatar: ""} -> []
          %{avatar: avatar} -> [avatar]
        end,
        render: fn
          %{value: value} = assigns when value == "" or is_nil(value) ->
            ~H"<p><%= Backpex.HTML.pretty_value(@value) %></p>"

          assigns ->
            ~H'<img class="h-10 w-auto" src={avatar_file_url(@value)} />'
        end,
        align: :center
      },
      username: %{
        module: Backpex.Fields.Text,
        label: "Username",
        searchable: true,
        panel: :names,
        index_editable: true
      },
      full_name: %{
        module: Backpex.Fields.Text,
        label: "Full Name",
        searchable: true,
        except: [:edit, :new],
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
        panel: :names
      },
      first_name: %{
        module: Backpex.Fields.Text,
        label: "First Name",
        only: [:edit, :new],
        searchable: true,
        panel: :names
      },
      last_name: %{
        module: Backpex.Fields.Text,
        label: "Last Name",
        only: [:edit, :new],
        searchable: true,
        panel: :names
      },
      age: %{
        module: Backpex.Fields.Number,
        label: "Age"
      },
      role: %{
        module: Backpex.Fields.Select,
        label: "Role",
        options: [Admin: "admin", User: "user"],
        prompt: "Choose role..."
      },
      posts: %{
        module: Backpex.Fields.HasMany,
        label: "Posts",
        display_field: :title,
        orderable: false,
        searchable: false,
        live_resource: DemoWeb.PostLive
      },
      addresses: %{
        module: Backpex.Fields.HasManyThrough,
        label: "Addresses",
        display_field: :full_address,
        except: [:index],
        orderable: false,
        searchable: false,
        live_resource: DemoWeb.AddressLive,
        pivot_fields: [
          type: %{
            module: Backpex.Fields.Select,
            label: "Address Type",
            options: [Shipping: "shipping", Billing: "billing"],
            prompt: "Choose address type..."
          },
          primary: %{
            module: Backpex.Fields.Boolean,
            label: "Primary"
          }
        ],
        options_query: fn query, _assigns ->
          select_merge(
            query,
            [a],
            %{full_address: fragment("concat(?, ', ', ?, ' ', ?, ', ', ?)", a.street, a.zip, a.city, a.country)}
          )
        end
      },
      social_links: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Social links",
        type: :embed,
        except: [:index],
        child_fields: [
          label: %{
            module: Backpex.Fields.Text,
            label: "Label",
            class: "w-1/3"
          },
          url: %{
            module: Backpex.Fields.Text,
            label: "URL",
            class: "w-2/3"
          }
        ]
      },
      web_links: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Web links",
        type: :embed,
        except: [:index],
        child_fields: [
          label: %{
            module: Backpex.Fields.Text,
            label: "Label"
          },
          url: %{
            module: Backpex.Fields.Text,
            label: "URL"
          },
          notes: %{
            module: Backpex.Fields.Textarea,
            label: "Notes"
          }
        ]
      },
      permissions: %{
        module: Backpex.Fields.MultiSelect,
        label: "Permissions",
        options: fn _assigns -> [{"Delete", "delete"}, {"Edit", "edit"}, {"Show", "show"}] end
      }
    ]
  end

  @impl Backpex.LiveResource
  def metrics do
    [
      min_age: %{
        module: Backpex.Metrics.Value,
        label: "Min age",
        class: "w-full lg:w-1/3",
        select: dynamic([u], min(u.age)),
        format: fn value ->
          Integer.to_string(value) <> " years"
        end
      },
      max_age: %{
        module: Backpex.Metrics.Value,
        label: "Max age",
        class: "w-full lg:w-1/3",
        select: dynamic([u], max(u.age)),
        format: fn value ->
          Integer.to_string(value) <> " years"
        end
      }
    ]
  end

  def put_upload_change(socket, change, item, uploaded_entries, removed_entries, :validate) do
    case {uploaded_entries, removed_entries} do
      {{[] = _completed, [entry | _] = _in_progress}, _removed} ->
        Map.put(change, "avatar", avatar_file_name(entry))

      {_uploaded, [entry]} ->
        Map.put(change, "avatar", "")

      _other ->
        change
    end
  end

  def put_upload_change(_socket, change, item, uploaded_entries, removed_entries, :insert) do
    case {uploaded_entries, removed_entries} do
      {{[entry | _] = _completed, _in_progress}, _removed} ->
        Map.put(change, "avatar", avatar_file_name(entry))

      {_uploaded, [entry]} ->
        Map.put(change, "avatar", "")

      _other ->
        change
    end
  end

  # sobelow_skip ["Traversal"]
  defp consume_upload(_socket, %{path: path} = _meta, entry) do
    file_name = avatar_file_name(entry)
    dest = Path.join([:code.priv_dir(:demo), "static", avatar_static_dir(), file_name])

    File.cp!(path, dest)

    {:ok, avatar_file_url(file_name)}
  end

  defp remove_uploads(socket, removed_entries) do
    # remove uploads
  end

  defp avatar_static_dir, do: Path.join(["uploads", "user", "avatar"])

  defp avatar_file_url(file_name) do
    static_path = Path.join([avatar_static_dir(), file_name])
    Phoenix.VerifiedRoutes.static_url(DemoWeb.Endpoint, "/" <> static_path)
  end

  defp avatar_file_name(entry) do
    [ext | _] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end
end
