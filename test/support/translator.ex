defmodule Backpex.Test.Translator do
  @moduledoc "Interpolates the bindings of a Backpex message, like the translator function of an app without Gettext."

  def translate({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _match -> to_string(value) end)
    end)
  end
end
