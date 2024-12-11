defmodule Backpex.AutoLiveResource do
  @moduledoc """
  Creates a live resource by inspecting the given ecto schema.

  ## Example

  To use this functionality in your app, first define a new module
  in your application which encapsulates
  data that is common to all resources (repo, pubsub and layouts)

      defmodule MyAppWeb.LiveResource do
        use Backpex.AutoLiveResource,
          repo: MyApp.Repo,
          layout: {MyAppWeb.Layouts, :admin},
          pubsub: MyApp.PubSub
      end

  Now, you can define a new live resource using the module above

      defmodule MyAppWeb.MyResourceLive do
        use MyAppWeb.LiveResource,
          resource: MyApp.MyContext.MyResource
      end
  """

  defmodule Params do
    @moduledoc false

    # This struct gathers all strings, modules and atom names
    # we need to generate our live_resource.
    # Some of these words have been inferred from the name
    # of the ecto schema, but users of `%Params{}` will never
    # need to know how words were inferred.

    defstruct repo: nil,
              layout: nil,
              pubsub: nil,
              resource: nil,
              singular_name: nil,
              plural_name: nil,
              topic: nil,
              event_prefix: nil,
              update_changeset: nil,
              create_changeset: nil,
              field_overrides: nil,
              fields: nil
  end

  defmodule EctoField do
    @moduledoc false

    defstruct name: nil,
              type: nil,
              input_module: nil,
              label: nil,
              extra: %{}
  end

  defmodule Fields do
    @moduledoc false

    defstruct ecto_fields: [],
              # We don't support overrides yet
              overrides: %{}
  end



  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    layout = Keyword.fetch!(opts, :layout)
    pubsub = Keyword.fetch!(opts, :pubsub)
    singular_name = Keyword.get(opts, :singular_name)
    plural_name = Keyword.get(opts, :plural_name)
    topic = Keyword.get(opts, :topic)
    event_prefix = Keyword.get(opts, :event_prefix)

    quote do
      defmacro __using__(opts) do
        debug = Keyword.get(opts, :debug)

        resource_ast = Keyword.fetch!(opts, :resource)
        {resource, []} = Code.eval_quoted(resource_ast)

        resource_string_alias = Module.split(resource) |> Enum.at(-1)
        resource_underscore = Macro.underscore(resource_string_alias)

        singular_name = unquote(singular_name) || resource_string_alias
        plural_name = unquote(plural_name) || Inflex.pluralize(singular_name)

        topic = unquote(topic) || resource_underscore
        event_prefix = unquote(event_prefix) || "#{resource_underscore}_"

        update_changeset = Keyword.get(opts, :update_changeset, nil)
        create_changeset = Keyword.get(opts, :create_changeset, nil)

        resource_exports = resource.__info__(:functions)

        params =
          %Params{
            repo: unquote(repo),
            layout: unquote(layout),
            pubsub: unquote(pubsub),
            resource: resource,
            singular_name: singular_name,
            plural_name: plural_name,
            topic: topic,
            event_prefix: event_prefix,
            update_changeset: update_changeset,
            create_changeset: create_changeset
          }

        ast = unquote(__MODULE__).build_resource_use_macro(params)

        if not is_nil(debug) do
          code =
            ast
            |> Macro.to_string()
            |> Code.format_string!()

          case debug do
            # Log output into console
            true ->
              IO.puts(code)

            path when is_binary(path) ->
              File.write!(path, code)

            other ->
              raise ArgumentError, """
                The :debug options for a Backpex.AutoLiveResource must be one of the following:

                  - nil
                  - boolean (true or false)
                  - a binary representing the path to a file

                The following value was given: #{inspect(other)}
                """
          end
        end

        # Return the AST for the module contents
        ast
      end
    end
  end

  @doc false
  def build_resource_use_macro(%Params{} = params) do
    functions = params.resource.__info__(:functions)

    update_changeset_def = build_update_changeset_definition(params, functions)
    create_changeset_def = build_create_changeset_definition(params, functions)

    backpex_fields =
      params.resource
      |> ecto_fields_from_module([])
      |> backpex_fields_from_ecto_fields()

    quote do
      # Require the resource module so that the views are recompiled
      # if the ecto schema changes. Without this require statement,
      # there won't be an explicit compile-time dependency between
      # the ecto schema and the live resource
      require unquote(params.resource)

      # def __update_changeset(...)
      unquote(update_changeset_def)

      # def __changeset_changeset(...)
      unquote(create_changeset_def)

      use Backpex.LiveResource,
        adapter_config: [
          schema: unquote(params.resource),
          repo: unquote(params.repo),
          # Use the functions we have defined in this module just above
          # this `use Backpex.LiveResource` call
          update_changeset: &__MODULE__.__update_changeset/3,
          create_changeset: &__MODULE__.__create_changeset/3,
          item_query: &__MODULE__.item_query/3
        ],
        layout: unquote(params.layout),
        pubsub: [
          name: unquote(params.pubsub),
          topic: unquote(params.topic),
          event_prefix: unquote(params.event_prefix)
        ]

      @impl Backpex.LiveResource
      # TODO: internationalize this
      def singular_name, do: unquote(params.singular_name)

      @impl Backpex.LiveResource
      # TODO: internationalize this
      def plural_name, do: unquote(params.plural_name)

      @impl Backpex.LiveResource
      def fields do
        unquote(Macro.escape(backpex_fields))
      end

      defoverridable fields: 0,
                     singular_name: 0,
                     plural_name: 0
    end
  end

  @doc """
  Converts an atom or a string to a something you'd display
  to English-speaking humans. The implementation is very simple
  and will probably only work for atoms and module names which
  follow simple capitalization rules.
  """
  def humanize(atom) when is_atom(atom),
    do: humanize(Atom.to_string(atom))

  def humanize(bin) when is_binary(bin) do
    bin
    |> Macro.underscore()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp input_for(_resource, _field, :string) do
    {Backpex.Fields.Text, _extra = %{}}
  end

  defp input_for(_resource, _field, :text) do
    {Backpex.Fields.Text, _extra = %{}}
  end

  defp input_for(_resource, _field, :integer) do
    {Backpex.Fields.Number, _extra = %{}}
  end

  defp input_for(_resource, _field, :float) do
    {Backpex.Fields.Text, _extra = %{}}
  end

  defp input_for(_resource, _field, date) when date in [:date, :utc_date] do
    # By default render datetimes in a sensible format;
    # TODO: customize this somehow.
    {Backpex.Fields.Date, _extra = %{format: "%Y-%m-%d"}}
  end

  defp input_for(_resource, _field, date) when date in [:datetime, :utc_datetime] do
    # By default render datetimes in a sensible format;
    # TODO: customize this somehow.
    {Backpex.Fields.DateTime, _extra = %{format: "%Y-%m-%d %H:%M:%S"}}
  end

  defp input_for(resource, field, :id) do
    assoc_field =
      Enum.find(resource.__schema__(:associations), fn assoc_field ->
        assoc = resource.__schema__(:association, assoc_field)
        assoc.owner_key == field
      end)

    assoc = resource.__schema__(:association, assoc_field)

    case assoc do
      # We only support BelongsTo associations
      %Ecto.Association.BelongsTo{} = assoc ->
        related_module = assoc.related

        input_module = Backpex.Fields.BelongsTo

        input_extras = %{
          display_field: get_default_display_field(related_module),
          prompt: ""
        }

        {input_module, input_extras}

      # All other associations are ignored
      _other ->
        {nil, %{}}
    end
  end

  defp get_default_display_field(ecto_schema) do
    # The display field will be the first string field.
    # Fields are searched in the order they appear in the ecto schema.
    # This is not configurable, but you can configure it
    # pretty easily by re-ordering the fields of the ecto schema.
    default_field =
      Enum.find(ecto_schema.__schema__(:fields), fn f ->
        ecto_schema.__schema__(:type, f) == :string
      end)

    if is_nil(default_field) do
      :id
    else
      default_field
    end
  end

  defp maybe_rename_field(resource, field_name) do
    # If the field is an ID, we assume it's a foreign key.
    # We inspect the associations to see what's
    # the association field name for the foreign key.
    # The field with type ID will exist whether it's defined
    # by the `field()` function or by the `belongs_to()` function.
    if resource.__schema__(:type, field_name) == :id do
      assoc_field_name =
        Enum.find(resource.__schema__(:associations), fn assoc_field ->
          assoc = resource.__schema__(:association, assoc_field)
          assoc.owner_key == field_name
        end)

      assoc_field_name
    else
      # If it is anything else, just return the field name.
      field_name
    end
  end

  # Introspect the ecto schema to create the appropriate ecto fields.
  # These fields will be converted into backpex fields.
  defp ecto_fields_from_module(resource, _overrides) do
    names = resource.__schema__(:fields)
    types = for f <- names, do: resource.__schema__(:type, f)
    inputs = for {f, t} <- Enum.zip(names, types), do: input_for(resource, f, t)

    for {name, type, input} <- Enum.zip([names, types, inputs]), name != :id do
      name = maybe_rename_field(resource, name)

      {input_module, input_extra} = input

      label = humanize(name)

      extra =
        if name in [:inserted_at, :updated_at] do
          input_extra
          |> Map.put_new(:readonly, true)
          |> Map.put_new(:except, [:new])
        else
          input_extra
        end

      %EctoField{
        name: name,
        type: type,
        input_module: input_module,
        label: label,
        extra: extra
      }
    end
  end

  # Convert the ecto fields into something that's used by backpex
  defp backpex_fields_from_ecto_fields(ecto_fields) do
    for f <- ecto_fields, not is_nil(f.input_module) do
      value = %{
        module: f.input_module,
        label: f.label
      }

      {f.name, Map.merge(value, f.extra)}
    end
  end

  defp build_update_changeset_definition(params, resource_functions) do
    # We have to define `__update_changeser/3` three times because
    # in some situations we will want to ignore the `opts` argument.
    # This leads to some unnecessary repetition, but it's the simplest
    # way of avoiding annoying warnings without complicating the quoted
    # expressions that much.
    cond do
      params.update_changeset ->
        quote do
          def __update_changeset(item, attrs, opts) do
            unquote(params.update_changeset).(item, attrs, opts)
          end
        end

      {:update_changeset, 3} in resource_functions ->
        quote do
          def __update_changeset(item, attrs, opts) do
            unquote(params.resource).update_changeset(item, attrs, opts)
          end
        end

      {:changeset, 2} in resource_functions ->
        quote do
          def __update_changeset(item, attrs, _opts) do
            unquote(params.resource).changeset(item, attrs)
          end
        end
    end
  end

  defp build_create_changeset_definition(params, resource_functions) do
    # We have to define `__update_changeser/3` three times because
    # in some situations we will want to ignore the `opts` argument.
    # This leads to some unnecessary repetition, but it's the simplest
    # way of avoiding annoying warnings without complicating the quoted
    # expressions that much.
    cond do
      params.create_changeset ->
        quote do
          def __create_changeset(item, attrs, opts) do
            unquote(params.create_changeset).(item, attrs, opts)
          end
        end

      {:create_changeset, 3} in resource_functions ->
        quote do
          def __create_changeset(item, attrs, opts) do
            unquote(params.resource).update_changeset(item, attrs, opts)
          end
        end

      {:changeset, 2} in resource_functions ->
        quote do
          def __create_changeset(item, attrs, _opts) do
            unquote(params.resource).changeset(item, attrs)
          end
        end
    end
  end
end
