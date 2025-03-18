defmodule Backpex do
  @moduledoc """
  Backpex provides an easy way to manage existing resources in your application.
  """

  @doc """
  Translates a string.

  The type must be `:general` or `:error`.
  """
  def translate(live_resource, msg, type \\ :general)

  def translate(live_resource, {msg, opts}, type) do
    live_resource.translate({msg, opts}, type)
  end

  def translate(live_resource, msg, type), do: translate(live_resource, {msg, %{}}, type)

  def translator_from_config(type) do
    key =
      case type do
        :error -> :error_translator_function
        _type -> :translator_function
      end

    case Application.get_env(:backpex, key) do
      {module, function} ->
        &apply(module, function, [&1])

      nil ->
        nil
    end
  end

  def default_translate({msg, opts}) do
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
