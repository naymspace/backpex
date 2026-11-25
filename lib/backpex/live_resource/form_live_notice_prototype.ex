defmodule Backpex.LiveResource.FormLiveNoticePrototype do
  @moduledoc false
  # PROTOTYPE, throwaway. Branch `prototype/live-notice` only, never merged.
  #
  # Question (https://github.com/naymspace/backpex/issues/2577): what does an open edit form show when a PubSub
  # `updated` / `deleted` event for the same item arrives, and when does the form's base item move?
  #
  # Four variants on the existing edit route, switched by `?variant=`:
  #
  #   * `banner`   - one notice above the form: take over their changes or discard mine.
  #   * `markers`  - a note under every field someone else changed: use theirs / keep mine per field.
  #   * `takeover` - values of fields the admin hasn't touched are taken over silently.
  #   * `nothing`  - nothing until the save (the save's conflict handling decides).
  #
  # Base item rule used by every take-over: a taken-over field gets the other admin's value in the base item, a field
  # the admin changed keeps its old base value (so a clash still becomes a conflict at the save), unless the admin
  # explicitly chose "keep mine" for it.

  use BackpexWeb, :html

  alias Backpex.LiveResource
  alias Backpex.Resource

  @variants ~w(banner markers takeover nothing)

  def variants, do: @variants

  # -- state -------------------------------------------------------------------------------------------------------

  def init(socket) do
    %{live_resource: live_resource, fields: fields} = socket.assigns
    schema = live_resource.adapter_config(:schema)

    keys =
      Enum.flat_map(fields, fn {name, opts} ->
        cond do
          name in schema.__schema__(:fields) ->
            [%{key: name, field: name, label: opts[:label] || to_string(name)}]

          match?(%{cardinality: :one, owner_key: _key}, schema.__schema__(:association, name)) and
              schema.__schema__(:association, name).relationship == :parent ->
            [%{key: schema.__schema__(:association, name).owner_key, field: name, label: opts[:label]}]

          true ->
            []
        end
      end)

    assign(socket, :proto, %{variant: "banner", remote: nil, events: [], keys: keys, dry_run: nil})
  end

  def put_variant(socket, variant) when variant in @variants, do: update(socket, :proto, &%{&1 | variant: variant})
  def put_variant(socket, _variant), do: socket

  def same_item?(socket, other) do
    %{live_resource: live_resource, item: item} = socket.assigns
    to_string(LiveResource.primary_value(other, live_resource)) == to_string(LiveResource.primary_value(item, live_resource))
  end

  def handle_remote(socket, :deleted) do
    socket
    |> update(:proto, &%{&1 | remote: :deleted, dry_run: nil, events: log(&1.events, "deleted")})
  end

  def handle_remote(socket, remote_item) do
    socket = update(socket, :proto, &%{&1 | remote: remote_item, dry_run: nil})
    theirs = socket |> rows() |> Enum.filter(& &1.theirs?) |> Enum.map(& &1.label)
    socket = update(socket, :proto, &%{&1 | events: log(&1.events, "updated: " <> Enum.join(theirs, ", "))})

    case socket.assigns.proto.variant do
      "takeover" -> take_over_untouched(socket)
      _variant -> socket
    end
  end

  defp log(events, text), do: Enum.take(["#{Time.utc_now() |> Time.truncate(:second)} #{text}" | events], 6)

  @doc "One row per compared field: base, form, latest known (PubSub), mine?, theirs?, conflict?"
  def rows(%{assigns: assigns}), do: rows(assigns)

  def rows(%{proto: proto, item: base, changeset: changeset}) do
    remote = if is_map(proto.remote), do: proto.remote

    Enum.map(proto.keys, fn %{key: key} = row ->
      base_value = Map.get(base, key)
      form_value = Ecto.Changeset.get_field(changeset, key)
      mine? = Map.has_key?(changeset.changes, key)
      remote_value = remote && Map.get(remote, key)
      # Their change counts only where it differs from the base and from what the form shows (an echo of my own save
      # or the same value as mine is nothing to tell).
      theirs? = remote != nil and remote_value != base_value and remote_value != form_value

      Map.merge(row, %{
        base: base_value,
        form: form_value,
        remote: remote_value,
        mine?: mine?,
        theirs?: theirs?,
        conflict?: mine? and theirs?
      })
    end)
  end

  # -- take-over: moves the base item ------------------------------------------------------------------------------

  def take_over_untouched(socket) do
    keys = for row <- rows(socket), row.theirs? and not row.mine?, do: row.key
    move_base(socket, keys, [])
  end

  def use_theirs(socket, key), do: move_base(socket, [key], [key])
  def keep_mine(socket, key), do: move_base(socket, [key], [])

  # `keys` get the remote value in the base item; `drop_mine` are removed from the admin's changes.
  defp move_base(socket, [], _drop_mine), do: socket

  defp move_base(socket, keys, drop_mine) do
    %{item: base, changeset: changeset, proto: %{remote: remote}} = socket.assigns
    new_base = Enum.reduce(keys, base, &Map.put(&2, &1, Map.get(remote, &1)))
    mine = changeset.changes |> Map.keys() |> Kernel.--(drop_mine) |> Enum.map(&to_string/1)
    params = Map.take(changeset.params || %{}, mine)

    rebuild(socket, new_base, params)
  end

  def discard_mine(socket) do
    %{live_resource: live_resource, fields: fields, item: base} = socket.assigns
    fresh = Resource.get!(LiveResource.primary_value(base, live_resource), fields, socket.assigns, live_resource)

    socket
    |> update(:proto, &%{&1 | remote: nil})
    |> rebuild(fresh, %{})
  end

  defp rebuild(socket, base, params) do
    %{live_resource: live_resource, fields: fields} = assigns = socket.assigns
    changeset = Resource.change(base, params, fields, assigns, live_resource, assocs: Map.get(assigns, :assocs, []))

    socket
    |> update(:proto, &%{&1 | dry_run: nil})
    |> assign(:item, base)
    |> assign(:changeset, changeset)
  end

  # -- dry-run of the save check of #2574 (reads the row now, catches writers outside Backpex) ----------------------

  def dry_run(socket) do
    %{live_resource: live_resource, item: base} = socket.assigns
    repo = live_resource.adapter_config(:repo)
    schema = live_resource.adapter_config(:schema)
    current = repo.get(schema, LiveResource.primary_value(base, live_resource))

    result =
      case current do
        nil ->
          "gone"

        current ->
          conflicts =
            for row <- rows(socket), row.mine?, Map.get(current, row.key) not in [row.base, row.form], do: row.label

          if conflicts == [], do: "saved", else: "conflict: " <> Enum.join(conflicts, ", ")
      end

    update(socket, :proto, &%{&1 | dry_run: result})
  end

  # -- simulate another admin --------------------------------------------------------------------------------------

  def simulate(socket, what) do
    %{live_resource: live_resource, item: base} = socket.assigns
    repo = live_resource.adapter_config(:repo)
    schema = live_resource.adapter_config(:schema)
    id = LiveResource.primary_value(base, live_resource)
    current = repo.get!(schema, id)
    stamp = Time.utc_now() |> Time.truncate(:second) |> Time.to_string()

    case what do
      "delete" ->
        # Demo-specific: posts_tags has no ON DELETE.
        import Ecto.Query
        repo.delete_all(from(pt in "posts_tags", where: pt.post_id == type(^id, Ecto.UUID)))
        {:ok, deleted} = repo.delete(current)
        Resource.broadcast({:ok, deleted}, "deleted", live_resource)

      "sql" ->
        import Ecto.Query
        repo.update_all(from(i in schema, where: i.id == ^id), set: [title: "Set via SQL #{stamp}"])

      _attr ->
        attrs =
          case what do
            "title" -> %{title: "Edited elsewhere #{stamp}"}
            "body" -> %{body: "Edited elsewhere #{stamp}\n\n" <> (current.body || "")}
            "published" -> %{published: not current.published}
            "same_title" -> %{title: Ecto.Changeset.get_field(socket.assigns.changeset, :title)}
          end

        current |> Ecto.Changeset.change(attrs) |> repo.update() |> Resource.broadcast("updated", live_resource)
    end

    socket
  end

  # -- components --------------------------------------------------------------------------------------------------

  def deleted?(assigns), do: match?(%{proto: %{remote: :deleted, variant: v}} when v != "nothing", assigns)

  attr :proto, :map, required: true
  attr :rows, :list, required: true
  attr :back, :string, required: true

  def banner(%{proto: %{remote: :deleted, variant: variant}} = assigns) when variant != "nothing" do
    ~H"""
    <div role="alert" class="alert alert-error mb-4">
      <span>
        <strong>Someone else deleted this post.</strong>
        It can't be saved anymore. Your input stays here so you can copy it.
      </span>
      <.link navigate={@back} class="btn btn-sm">Back to list</.link>
    </div>
    """
  end

  def banner(%{proto: %{variant: "banner"}} = assigns) do
    assigns =
      assigns
      |> assign(:theirs, Enum.filter(assigns.rows, &(&1.theirs? and not &1.mine?)))
      |> assign(:conflicts, Enum.filter(assigns.rows, & &1.conflict?))

    ~H"""
    <div :if={@theirs != [] or @conflicts != []} role="status" class={["alert mb-4", if(@conflicts != [], do: "alert-warning", else: "alert-info")]}>
      <div>
        <p><strong>Someone else saved this post</strong> while you were editing it.</p>
        <p :if={@theirs != []} class="text-sm">
          Their changes: {Enum.map_join(@theirs, ", ", & &1.label)}.
        </p>
        <p :if={@conflicts != []} class="text-sm">
          They also changed what you changed: {Enum.map_join(@conflicts, ", ", & &1.label)}.
          You'll choose when you save.
        </p>
      </div>
      <div class="flex gap-2">
        <button :if={@theirs != []} type="button" class="btn btn-sm btn-primary" phx-click="proto-take-over">
          Take over their changes
        </button>
        <button type="button" class="btn btn-sm" phx-click="proto-discard" data-confirm="Discard your changes?">
          Discard mine, reload
        </button>
      </div>
    </div>
    """
  end

  def banner(assigns), do: ~H""

  attr :row, :map, default: nil
  attr :variant, :string, required: true

  def marker(%{variant: "markers", row: %{theirs?: true}} = assigns) do
    ~H"""
    <div class={[
      "mx-4 -mt-1 mb-3 flex flex-wrap items-center gap-2 rounded-box px-3 py-2 text-sm sm:ml-[25%]",
      if(@row.conflict?, do: "bg-warning/20", else: "bg-info/15")
    ]}>
      <span :if={!@row.conflict?}>Someone else changed this to <q class="font-medium">{show(@row.remote)}</q>.</span>
      <span :if={@row.conflict?}>
        Someone else changed this to <q class="font-medium">{show(@row.remote)}</q> while you edited it.
      </span>
      <button type="button" class="btn btn-xs" phx-click="proto-use-theirs" phx-value-key={@row.key}>
        {if @row.conflict?, do: "Use theirs", else: "Take over"}
      </button>
      <button :if={@row.conflict?} type="button" class="btn btn-xs" phx-click="proto-keep-mine" phx-value-key={@row.key}>
        Keep mine
      </button>
    </div>
    """
  end

  def marker(assigns), do: ~H""

  defp show(value) when is_binary(value), do: String.slice(value, 0, 80)
  defp show(true), do: "Yes"
  defp show(false), do: "No"
  defp show(value), do: inspect(value)

  attr :proto, :map, required: true
  attr :rows, :list, required: true

  def overlay(assigns) do
    index = Enum.find_index(@variants, &(&1 == assigns.proto.variant))
    assigns = assign(assigns, prev: Enum.at(@variants, index - 1), next: Enum.at(@variants, rem(index + 1, 4)))

    ~H"""
    <details open class="bg-base-100 border-base-300 fixed right-3 bottom-20 z-50 max-w-[calc(100vw-1.5rem)] rounded-box border text-xs shadow-lg">
      <summary class="cursor-pointer px-3 py-2 font-semibold">PROTOTYPE state</summary>
      <div class="max-h-[50vh] overflow-auto px-3 pb-3">
        <table class="table-xs table">
          <thead>
            <tr><th>field</th><th>base</th><th>form</th><th>latest (PubSub)</th><th>mine</th><th>theirs</th></tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class={row.conflict? && "bg-warning/20"}>
              <td>{row.label}</td>
              <td class="max-w-32 truncate">{show(row.base)}</td>
              <td class="max-w-32 truncate">{show(row.form)}</td>
              <td class="max-w-32 truncate">{if is_map(@proto.remote), do: show(row.remote), else: "–"}</td>
              <td>{if row.mine?, do: "✎"}</td>
              <td>{if row.theirs?, do: if(row.conflict?, do: "⚠ conflict", else: "●")}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@proto.remote == :deleted} class="text-error mt-1">latest: deleted</p>
        <p class="mt-2">
          <button type="button" class="btn btn-xs" phx-click="proto-dry-run">Dry-run save check</button>
          <span :if={@proto.dry_run}>→ <strong>{@proto.dry_run}</strong></span>
        </p>
        <ul class="mt-2 opacity-70">
          <li :for={event <- @proto.events}>{event}</li>
        </ul>
      </div>
    </details>

    <div class="bg-neutral text-neutral-content fixed bottom-3 left-1/2 z-50 flex max-w-[calc(100vw-1.5rem)] -translate-x-1/2 flex-wrap items-center gap-2 rounded-full px-4 py-2 text-xs shadow-xl">
      <.link patch={"?variant=#{@prev}"} class="btn btn-xs btn-circle" aria-label="Previous variant">←</.link>
      <span class="min-w-20 text-center font-semibold">{@proto.variant}</span>
      <.link patch={"?variant=#{@next}"} class="btn btn-xs btn-circle" aria-label="Next variant">→</.link>
      <span class="opacity-60">| other admin:</span>
      <button :for={{what, label} <- [{"title", "title"}, {"body", "body"}, {"published", "published"}, {"same_title", "= my title"}, {"sql", "title via SQL"}, {"delete", "delete"}]}
        type="button"
        class={["btn btn-xs", what == "delete" && "btn-error"]}
        phx-click="proto-simulate"
        phx-value-what={what}
        data-confirm={what == "delete" && "Really delete this post in the demo DB?"}
      >
        {label}
      </button>
    </div>
    """
  end
end
