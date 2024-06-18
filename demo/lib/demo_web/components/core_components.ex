defmodule DemoWeb.CoreComponents do
  @moduledoc """
  Provides core components.
  """
  use Phoenix.Component

  @doc """
  Renders the analytics snippet.
  """
  def analytics(assigns) do
    assigns = assign(assigns, analytics_domain: Application.get_env(:demo, DemoWeb.Endpoint)[:url][:host])

    ~H"""
    <script
      :if={Application.get_env(:demo, :analytics)}
      defer
      data-domain={@analytics_domain}
      src="https://plausible.io/js/plausible.js"
    >
    </script>
    """
  end

  @doc """
  Builds sentry meta tag.
  """
  def sentry_meta_tag(assigns) do
    assigns = assign(assigns, :dsn, Application.get_env(:sentry, :dsn))

    ~H"""
    <meta :if={@dsn} name="sentry-dsn" content={@dsn} />
    """
  end

  @doc """
  Translates backpex message using gettext.
  """
  def translate_backpex({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(DemoWeb.Gettext, "backpex", msg, msg, count, opts)
    else
      Gettext.dgettext(DemoWeb.Gettext, "backpex", msg, opts)
    end
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(DemoWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(DemoWeb.Gettext, "errors", msg, opts)
    end
  end
end
