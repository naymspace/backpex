defmodule Backpex.HTML.CoreComponents do
  @moduledoc """
  Provides core components for Backpex.
  """
  use BackpexWeb, :html

  require Backpex

  @doc """
  Renders a Heroicons icon.
  """
  @doc type: :component

  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global, default: %{"aria-hidden": "true", viewBox: "0 0 24 24", fill: "currentColor"}

  def icon(%{name: "hero-" <> _name} = assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest} />
    """
  end
end
