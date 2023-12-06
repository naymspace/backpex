defmodule Demo.Newsletter do
  @moduledoc """
  Manage newsletter subscriptions.
  """

  alias Demo.Newsletter.Brevo
  alias Demo.Newsletter.Contact
  alias Ecto.Changeset

  @doc """
  Create changeset for contact with given attributes.
  """
  def change_contact(contact_or_changeset, attrs \\ %{}) do
    Contact.changeset(contact_or_changeset, attrs)
  end

  @doc """
  Subscribe to the newsletter.
  """
  def subscribe(params) do
    changeset =
      %Contact{}
      |> change_contact(params)
      |> Map.put(:action, :insert)

    if changeset.valid? do
      case Brevo.double_optin_confirmation(changeset.changes.email) do
        {:ok, %Tesla.Env{status: 201}} ->
          {:ok, changeset}

        {:ok, %Tesla.Env{status: 204}} ->
          {:ok, changeset}

        {:ok, %Tesla.Env{status: 400, body: %{"message" => message}}} ->
          {:error, Changeset.add_error(changeset, :email, message)}

        {:error, _message} ->
          {:error, Changeset.add_error(changeset, :email, "something went wrong")}
      end
    else
      {:error, changeset}
    end
  end
end
