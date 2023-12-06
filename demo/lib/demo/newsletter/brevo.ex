defmodule Demo.Newsletter.Brevo do
  @moduledoc """
  Interact with the Brevo API.
  """

  @doc """
  Create Contact via DOI (Double-Opt-In) Flow.

  https://developers.brevo.com/reference/createdoicontact
  """
  def double_optin_confirmation(email) do
    client()
    |> Tesla.post("/contacts/doubleOptinConfirmation", %{
      email: email,
      includeListIds: config!(:include_list_ids),
      templateId: config!(:template_id),
      redirectionUrl: "https://backpex.live"
    })
  end

  @doc """
  Create a Tesla client with dynamic runtime middlewares.

  https://hexdocs.pm/tesla/readme.html#runtime-middleware
  """
  def client do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.brevo.com/v3"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"api-key", config!(:api_key)}]}
    ]

    Tesla.client(middleware)
  end

  defp config!(key), do: Application.fetch_env!(:demo, __MODULE__)[key]
end
