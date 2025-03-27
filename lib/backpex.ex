defmodule Backpex do
  @moduledoc """
  Backpex provides an easy way to manage existing resources in your application.
  """

  @doc false
  defmacro __(msg, live_resource \\ nil) do
    {msg, opts} =
      case msg do
        {msg, opts} -> {msg, opts}
        msg -> {msg, Macro.escape(%{})}
      end

    quote do
      use Gettext, backend: Backpex.Gettext

      # mark translation for extraction
      Gettext.Macros.dgettext_noop("backpex", unquote(msg))

      Backpex.translate({unquote(msg), unquote(opts)}, unquote(live_resource))
    end
  end

  @doc """
  Translates a text with the configured translator_function. If a live_resource is given, it calls the LiveResource's translate callback.

  ## Examples

      Backpex.translate("Hello")

      Backpex.translate({"Hello %{name}", %{name: "World"}})

      Backpex.translate("Welcome", MyApp.LiveResource)
  """
  def translate(msg, live_resource \\ nil)

  def translate(msg, live_resource) when is_binary(msg) do
    translate({msg, %{}}, live_resource)
  end

  def translate({msg, opts}, nil = _live_resource) do
    translate_func = translate_func(:general)
    translate_func.({msg, opts})
  end

  def translate({msg, opts}, live_resource) do
    live_resource.translate({msg, opts})
  end

  @doc """
  Translates an error text with the configured error_translator_function.

  ## Examples

      Backpex.translate_error("can't be blank")

      Backpex.translate_error({"must be greater than %{number}", %{number: 0}})
  """
  def translate_error(msg) when is_binary(msg) do
    translate_error({msg, %{}})
  end

  def translate_error({msg, opts}) do
    translate_func = translate_func(:error)
    translate_func.({msg, opts})
  end

  defp translate_func(type) when type in [:general, :error] do
    key =
      case type do
        :error -> :error_translator_function
        :general -> :translator_function
      end

    case Application.get_env(:backpex, key) do
      {module, function} ->
        &apply(module, function, [&1])

      nil ->
        IO.warn("""
        Backpex can't find the #{inspect(key)} configuration in your config.

        Hint: you can set up a `translator_function` and `error_translator_function` to route all strings to your application helpers:

        config :backpex,
          translator_function: {MyAppWeb.CoreComponents, :translate_backpex},
          error_translator_function: {MyAppWeb.CoreComponents, :translate_error}

        A fallback message translator will be used.
        """)

        &default_translate/1
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
            The fallback message translator of Backpex could not handle replacing the given value.

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
