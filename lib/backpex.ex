defmodule Backpex do
  @moduledoc """
  Backpex provides an easy way to manage existing resources in your application.
  """

  @doc """
  Marks the given message for extraction and translates it.
  """
  defmacro t(msg, opts \\ %{}, live_resource \\ nil) do
    quote do
      use Gettext, backend: Backpex.Gettext
      require Gettext.Macros

      opts = unquote(opts)

      # mark translation for extraction
      Gettext.Macros.dgettext_noop("backpex", unquote(msg))

      live_resource = unquote(live_resource)

      # TODO: extract to function
      case live_resource do
        nil ->
          Backpex.translate({unquote(msg), opts})

        live_resource ->
          live_resource.translate({unquote(msg), opts})
      end
    end
  end

  def translate(msg, type \\ :general)

  def translate({msg, opts}, type) when type in [:general, :error] do
    translate_func = translate_func(type)
    translate_func.({msg, opts})
  end

  def translate(msg, type), do: translate({msg, %{}}, type)

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
