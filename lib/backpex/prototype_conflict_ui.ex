defmodule Backpex.PrototypeConflictUI do
  @moduledoc false
  # PROTOTYPE, throw away. Lives only on the branch `prototype/conflict-ui`.
  #
  # Question (https://github.com/naymspace/backpex/issues/2576): what does the admin see and choose when
  # a save hits a conflict? Four variants on the existing edit form, switchable via `?variant=A|B|C|D`
  # and the floating bar at the bottom:
  #
  #   A  Error + reload        the save is refused; the only way out is to reload (and lose the changes)
  #   B  Compare per field     a dialog with base / mine / current per conflicting field, choice per field
  #   C  Overwrite anyway      a notice listing the fields, with "Overwrite anyway" or "Discard and reload"
  #   D  Rebase inline         the form takes over the current item at once, keeps the admin's changes and
  #                            marks the conflicting fields inline with "Use theirs"
  #
  # The conflict check fakes the decided three-way compare (#2574) without a row lock: re-read the row by
  # primary key, compare base (the item of the mount) / submitted / current per field the admin changed.
  # The bar's "simulate" buttons write the row behind Backpex' back (`update_all`, no PubSub), like a job.
  #
  # Enabled only with `config :backpex, :conflict_prototype, true` (demo dev config).

  use BackpexWeb, :html

  import Ecto.Query, only: [from: 2]

  alias Backpex.Resource

  @variants [
    {"A", "Error + reload"},
    {"B", "Compare per field"},
    {"C", "Overwrite anyway"},
    {"D", "Rebase inline"}
  ]

  def enabled?, do: Application.get_env(:backpex, :conflict_prototype, false)

  def variant(params) do
    keys = Enum.map(@variants, &elem(&1, 0))
    if params["variant"] in keys, do: params["variant"], else: "A"
  end

  ## Conflict check

  def check(assigns, params, assocs) do
    %{item: base, live_resource: live_resource, fields: fields} = assigns
    schema = live_resource.adapter_config(:schema)
    repo = live_resource.adapter_config(:repo)

    changeset = Resource.change(base, params, fields, assigns, live_resource, assocs: assocs, action: :update)

    case repo.get(schema, primary_value(base, live_resource)) do
      nil ->
        :gone

      current ->
        mine = Map.take(changeset.changes, schema.__schema__(:fields))

        conflicts =
          for {key, submitted} <- mine,
              base_value = Map.get(base, key),
              current_value = Map.get(current, key),
              current_value != base_value,
              current_value != submitted do
            entry(key, base_value, submitted, current_value, assigns)
          end

        if conflicts == [], do: :ok, else: {:conflict, %{fields: conflicts, mine: Map.keys(mine)}}
    end
  end

  def primary_value(item, live_resource), do: Map.fetch!(item, live_resource.config(:primary_key))

  defp entry(key, base, mine, current, assigns) do
    {field_name, field_options} = backpex_field(key, assigns)

    %{
      key: key,
      field_name: field_name,
      label: (field_options && field_options[:label]) || Phoenix.Naming.humanize(key),
      base: display(base, key, field_options, assigns),
      mine: display(mine, key, field_options, assigns),
      current: display(current, key, field_options, assigns),
      current_raw: current,
      resolved: false
    }
  end

  # The Backpex field that writes the schema field `key`: the field of the same name, or a `BelongsTo` whose
  # owner key it is.
  defp backpex_field(key, %{fields: fields, live_resource: live_resource}) do
    schema = live_resource.adapter_config(:schema)

    Enum.find(fields, {nil, nil}, fn {name, options} ->
      name == key or
        (options.module == Backpex.Fields.BelongsTo and
           match?(%{owner_key: ^key}, schema.__schema__(:association, name)))
    end)
  end

  defp display(nil, _key, _options, _assigns), do: "(empty)"
  defp display("", _key, _options, _assigns), do: "(empty)"

  defp display(value, key, %{module: Backpex.Fields.BelongsTo} = options, %{live_resource: live_resource}) do
    schema = live_resource.adapter_config(:schema)
    repo = live_resource.adapter_config(:repo)

    assoc =
      Enum.find_value(schema.__schema__(:associations), fn name ->
        case schema.__schema__(:association, name) do
          %{owner_key: ^key} = assoc -> assoc
          _other -> nil
        end
      end)

    case assoc && repo.get(assoc.queryable, value) do
      %{first_name: first, last_name: last} -> "#{first} #{last}"
      %{} = record -> to_string(Map.get(record, options[:display_field]) || value)
      _missing -> to_string(value)
    end
  end

  defp display(value, _key, _options, _assigns) when is_binary(value) do
    if String.length(value) > 140, do: String.slice(value, 0, 140) <> "…", else: value
  end

  defp display(value, _key, _options, _assigns), do: to_string(value)

  ## Simulations: another writer changes or deletes the row (no PubSub, like a job or SQL)

  def simulate_save(assigns) do
    %{item: item, live_resource: live_resource, fields: fields} = assigns
    schema = live_resource.adapter_config(:schema)
    repo = live_resource.adapter_config(:repo)
    pk = live_resource.config(:primary_key)
    id = primary_value(item, live_resource)
    current = repo.get!(schema, id)
    stamp = Time.utc_now() |> Time.truncate(:second) |> Time.to_string()

    set =
      for {name, %{module: module}} <- fields,
          module in [Backpex.Fields.Text, Backpex.Fields.Textarea],
          schema.__schema__(:type, name) == :string do
        {name, "#{Map.get(current, name)} [other admin #{stamp}]"}
      end

    repo.update_all(from(x in schema, where: field(x, ^pk) == ^id), set: set)
    Enum.map(set, fn {name, _value} -> name end)
  end

  def simulate_delete(assigns) do
    %{item: item, live_resource: live_resource} = assigns
    schema = live_resource.adapter_config(:schema)
    repo = live_resource.adapter_config(:repo)
    pk = live_resource.config(:primary_key)
    id = primary_value(item, live_resource)

    # Join rows of `many_to_many` first, as the demo's join tables don't cascade.
    for name <- schema.__schema__(:associations),
        %Ecto.Association.ManyToMany{join_through: join, join_keys: [{owner_key, _id} | _rest]} <-
          [schema.__schema__(:association, name)] do
      repo.delete_all(from(j in join, where: field(j, ^owner_key) == ^id))
    end

    repo.delete_all(from(x in schema, where: field(x, ^pk) == ^id))
  end

  ## Components

  attr :conflict, :any, required: true
  attr :variant, :string, required: true
  attr :live_resource, :atom, required: true
  attr :target, :any, required: true

  def notice(%{conflict: nil} = assigns), do: ~H""

  def notice(%{conflict: %{gone: true}} = assigns) do
    ~H"""
    <div role="alert" class="alert alert-error mb-4 flex flex-wrap">
      <Backpex.HTML.CoreComponents.icon name="hero-trash" class="size-5" />
      <div class="flex-1">
        <p class="font-semibold">This {@live_resource.singular_name()} was deleted while you were editing it.</p>
        <p class="text-sm">Your changes were not saved. Files you picked were not stored.</p>
      </div>
      <button type="button" class="btn btn-sm" phx-click="prototype-back" phx-target={@target}>
        Back to the list
      </button>
    </div>
    """
  end

  def notice(%{variant: "A"} = assigns) do
    ~H"""
    <div role="alert" class="alert alert-error mb-4 flex flex-wrap">
      <Backpex.HTML.CoreComponents.icon name="hero-exclamation-triangle" class="size-5" />
      <div class="flex-1">
        <p class="font-semibold">
          Someone else saved this {@live_resource.singular_name()} while you were editing it.
        </p>
        <p class="text-sm">
          Your changes to {Enum.map_join(@conflict.fields, ", ", & &1.label)} can't be saved.
          Reload to see the current version. Your changes will be lost.
        </p>
      </div>
      <button type="button" class="btn btn-sm" phx-click="prototype-reload" phx-target={@target}>
        Reload
      </button>
    </div>
    """
  end

  def notice(%{variant: "B"} = assigns) do
    ~H"""
    <div role="alert" class="alert alert-warning mb-4">
      <Backpex.HTML.CoreComponents.icon name="hero-exclamation-triangle" class="size-5" />
      <span>Not saved: someone else changed the same fields. Compare and decide below.</span>
    </div>
    <div class="modal modal-open" role="dialog" aria-modal="true" aria-labelledby="conflict-title">
      <div class="modal-box max-w-5xl">
        <h3 id="conflict-title" class="text-lg font-bold">
          Someone else saved this {@live_resource.singular_name()} while you were editing it
        </h3>
        <p class="text-base-content/70 py-2 text-sm">
          These fields were changed by you and by someone else. Choose which value to keep for each.
          Their changes to other fields are kept either way.
        </p>
        <form phx-submit="prototype-resolve" phx-target={@target}>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Field</th>
                  <th>When you opened it</th>
                  <th>Yours</th>
                  <th>Now (someone else)</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={entry <- @conflict.fields}>
                  <th>{entry.label}</th>
                  <td class="text-base-content/60 line-through">{entry.base}</td>
                  <td>
                    <label class="flex cursor-pointer items-start gap-2">
                      <input type="radio" class="radio radio-sm" name={"choice[#{entry.key}]"} value="mine" checked />
                      <span>{entry.mine}</span>
                    </label>
                  </td>
                  <td>
                    <label class="flex cursor-pointer items-start gap-2">
                      <input type="radio" class="radio radio-sm" name={"choice[#{entry.key}]"} value="theirs" />
                      <span>{entry.current}</span>
                    </label>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="modal-action">
            <button type="button" class="btn" phx-click="prototype-dismiss" phx-target={@target}>
              Back to the form
            </button>
            <button type="submit" class="btn btn-primary">Save with these values</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  def notice(%{variant: "C"} = assigns) do
    ~H"""
    <div role="alert" class="alert alert-warning mb-4 flex flex-col items-stretch">
      <div class="flex items-center gap-2">
        <Backpex.HTML.CoreComponents.icon name="hero-exclamation-triangle" class="size-5" />
        <p class="font-semibold">
          Someone else saved this {@live_resource.singular_name()} while you were editing it.
        </p>
      </div>
      <ul class="list-inside list-disc text-sm">
        <li :for={entry <- @conflict.fields}>
          <strong>{entry.label}</strong>: now “{entry.current}”, yours “{entry.mine}”
        </li>
      </ul>
      <div class="flex flex-wrap justify-end gap-2">
        <button type="button" class="btn btn-sm" phx-click="prototype-reload" phx-target={@target}>
          Discard my changes and reload
        </button>
        <button type="button" class="btn btn-sm btn-error" phx-click="prototype-overwrite" phx-target={@target}>
          Overwrite with my changes
        </button>
      </div>
    </div>
    """
  end

  def notice(%{variant: "D"} = assigns) do
    ~H"""
    <div role="status" class="alert alert-info mb-4">
      <Backpex.HTML.CoreComponents.icon name="hero-arrow-path" class="size-5" />
      <div>
        <p class="font-semibold">
          Not saved yet: someone else saved this {@live_resource.singular_name()} while you were editing it.
        </p>
        <p class="text-sm">
          The form now shows their version with your changes on top. {length(Enum.reject(@conflict.fields, & &1.resolved))} field(s) you both changed are marked below.
          Check them, then save again.
        </p>
      </div>
    </div>
    """
  end

  attr :conflict, :any, required: true
  attr :variant, :string, required: true
  attr :name, :atom, required: true
  attr :target, :any, required: true

  def inline_note(%{variant: "D", conflict: %{fields: fields}} = assigns) do
    assigns = assign(assigns, :entry, Enum.find(fields, &(&1.field_name == assigns.name and not &1.resolved)))

    ~H"""
    <div :if={@entry} class="border-warning bg-warning/10 mx-6 mb-3 rounded border-l-4 px-3 py-2 text-sm">
      <p>
        Someone else changed this to <strong>“{@entry.current}”</strong>
        (it was “{@entry.base}” when you opened it). Your value is in the field.
      </p>
      <button
        type="button"
        class="btn btn-xs btn-ghost mt-1"
        phx-click="prototype-use-theirs"
        phx-value-key={@entry.key}
        phx-target={@target}
      >
        Use theirs
      </button>
    </div>
    """
  end

  def inline_note(assigns), do: ~H""

  attr :variant, :string, required: true
  attr :current_url, :string, required: true
  attr :target, :any, required: true
  attr :simulated, :string, default: nil

  def switcher(assigns) do
    keys = Enum.map(@variants, &elem(&1, 0))
    index = Enum.find_index(keys, &(&1 == assigns.variant))

    assigns =
      assigns
      |> assign(:label, @variants |> Enum.at(index) |> elem(1))
      |> assign(:prev, url_for(assigns.current_url, Enum.at(keys, rem(index - 1 + length(keys), length(keys)))))
      |> assign(:next, url_for(assigns.current_url, Enum.at(keys, rem(index + 1, length(keys)))))

    ~H"""
    <div
      id="prototype-switcher"
      class="bg-neutral text-neutral-content fixed bottom-4 left-1/2 z-[1000] flex -translate-x-1/2 flex-wrap items-center justify-center gap-2 rounded-2xl px-3 py-2 text-sm shadow-2xl"
    >
      <span class="badge badge-warning badge-sm">PROTOTYPE</span>
      <.link
        patch={@prev}
        id="prototype-prev"
        class="btn btn-ghost btn-xs text-neutral-content"
        aria-label="Previous variant"
      >←</.link>
      <span class="min-w-40 text-center font-mono">{@variant} ({@label})</span>
      <.link patch={@next} id="prototype-next" class="btn btn-ghost btn-xs text-neutral-content" aria-label="Next variant">→</.link>
      <span class="opacity-40">|</span>
      <button type="button" class="btn btn-xs" phx-click="prototype-simulate-save" phx-target={@target}>
        Someone else saves
      </button>
      <button type="button" class="btn btn-xs" phx-click="prototype-simulate-delete" phx-target={@target}>
        Someone else deletes
      </button>
      <span :if={@simulated} role="status" class="text-warning w-full text-center text-xs">{@simulated}</span>
    </div>
    """
  end

  defp url_for(current_url, variant) do
    uri = URI.parse(current_url)
    query = (uri.query || "") |> URI.decode_query() |> Map.put("variant", variant) |> URI.encode_query()
    "#{uri.path}?#{query}"
  end
end
