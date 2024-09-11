defmodule Backpex.Ecto.EctoUtils do
  @moduledoc """
  Utilities for working with Ecto schemas and changesets.
  """

  @doc """
  Get the primary key field of an Ecto schema.

  This function can handle various input types:
  - Ecto schema module
  - Ecto schema struct
  - Ecto.Changeset

  ## Examples

      iex> get_primary_key_field(MyApp.User)
      :id

      iex> get_primary_key_field(%MyApp.User{})
      :id

      iex> get_primary_key_field(Ecto.Changeset.change(%MyApp.User{}))
      :id

  ## Errors

  Raises an error if:
  - No primary key is defined
  - A compound primary key is used (not supported)

  """
  def get_primary_key_field(schema)

  def get_primary_key_field(%Ecto.Changeset{data: data}), do: get_primary_key_field(data)

  def get_primary_key_field(%{__struct__: struct}) when is_atom(struct), do: get_primary_key_field(struct)

  def get_primary_key_field(module) when is_atom(module) do
    resolve_primary_key(&module.__schema__/1)
  end

  def get_primary_key_field(%{__schema__: schema_getter}) when is_function(schema_getter, 1) do
    resolve_primary_key(schema_getter)
  end

  defp resolve_primary_key(schema_getter) when is_function(schema_getter, 1) do
    case schema_getter.(:primary_key) do
      [id] -> id
      [] -> raise_no_primary_key_error()
      _multiple -> raise_compound_primary_key_error()
    end
  end

  defp raise_no_primary_key_error do
    raise ArgumentError, "No primary key found. Please define a primary key in your schema."
  end

  defp raise_compound_primary_key_error do
    raise ArgumentError, "Compound primary keys are not supported. Please use a single primary key."
  end
end
