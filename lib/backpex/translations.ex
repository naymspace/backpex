defmodule Backpex.Translations do
  @default_translations_docs [
    {"form.save",
     %{
       description: "Text for save/submit buttons on resource form views",
       bindings: [],
       text: {:gettext, "Save"}
     }},
    {"form.save_and_continue",
     %{
       description: "Text for \"Save & Continue editing\" buttons on resource form views",
       bindings: [],
       text: {:gettext, "Save & Continue editing"}
     }},
    {"form.cancel",
     %{
       description: "Text for cancel buttons on resource form views",
       bindings: [],
       text: {:gettext, "Cancel"}
     }},
    {"index.create_resource",
     %{
       description: "Text for button on index view that creates new resource",
       bindings: [:resource],
       text: {:gettext, "New %{resource}"}
     }}
  ]

  @translations @default_translations_docs
                |> Enum.map(fn {key, %{text: text}} -> {key, text} end)
                |> Enum.into(%{})

  @translate_opts_schema [
    live_resource: [
      doc: "The LiveResource module.",
      type: :atom,
      default: nil
    ],
    bindings: [
      doc: "Bindings that are passed to Gettext.",
      type: :map,
      default: %{}
    ]
  ]

  @doc """
  Translates the translation key. If `live_resource` option is provided, it first checks if there is a text override defined in the LiveResource's `text_overrides/0` function. If no override exists, it falls back to the default translation. The default translation is translated with the `translator_function` from the config.

  Raises if the key cannot be found in both text overrides and default translations.

  ### Options

  #{NimbleOptions.docs(@translate_opts_schema)}
  """

  def translate(key, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @translate_opts_schema)

    translation = get_translation(key, Keyword.get(opts, :live_resource))

    if is_nil(translation) do
      raise ArgumentError, """
      Translation key '#{key}' not found.
      """
    end

    process_translation(translation, Keyword.get(opts, :bindings))
  end

  defp get_translation(key, live_resource) when is_nil(live_resource) do
    default_translation(key)
  end

  defp get_translation(key, live_resource) do
    Map.get_lazy(live_resource.text_overrides(), key, fn ->
      default_translation(key)
    end)
  end

  defp default_translation(key) do
    Map.get(@translations, key)
  end

  defp process_translation({:gettext, text} = _translation, bindings) do
    translate_func = translate_func_from_config() || (&default_translate/1)

    translate_func.({text, bindings})
  end

  defp process_translation(translation, bindings) when is_function(translation, 1) do
    translation.(bindings)
  end

  defp process_translation(translation, _bindings) when is_binary(translation) do
    translation
  end

  defp translate_func_from_config do
    case Application.get_env(:backpex, :translator_function) do
      {module, function} ->
        &apply(module, function, [&1])

      nil ->
        nil
    end
  end

  defp default_translate({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      try do
        String.replace(acc, "%{#{key}}", to_string(value))
      rescue
        e ->
          IO.warn(
            """
            the fallback message translator for the form_field_error function cannot handle the given value.

            Hint: you can set up the `translator_function` and `error_translator_function` to route all strings to your application helpers:

              config :backpex, :translator_function, {MyAppWeb.Helpers, :translate_backpex}
              config :backpex, :error_translator_function, {MyAppWeb.ErrorHelpers, :translate_error}

            Given value: #{inspect(value)}

            Exception: #{Exception.message(e)}
            """,
            __STACKTRACE__
          )

          "invalid value"
      end
    end)
  end
end
