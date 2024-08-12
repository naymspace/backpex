defmodule Backpex.Ecto.EctoUtils do
  @moduledoc """
  Ecto utilities.
  """

  @doc """
  Get the primary key field of an Ecto schema.
  """
  # name of the schema module#
  def get_primary_key_field(%{__struct__: struct}) when is_atom(struct) do
    # the typechecker will shout that an atom does not have a __schema__ attribute
    resolve_primary_key!(struct)
  end

  # name of the schema module#
  def get_primary_key_field(module) when is_atom(module) do
    # the typechecker will shout that an atom does not have a __schema__ attribute if we access it directly
    # and suggests to use __schema__() function with parentheses
    resolve_primary_key!(&module.__schema__(&1))
  end

  def get_primary_key_field(%{__schema__: schema_getter}) when is_function(schema_getter) do
    resolve_primary_key!(schema_getter)
  end

  defp resolve_primary_key!(schema_getter) when is_function(schema_getter, 1) do
    ids = schema_getter.(:primary_key)

    case length(ids) do
      1 ->
        hd(ids)

      0 ->
        raise """
        No primary key found. Please define a primary key.
        """

      _ ->
        raise """
        Compound primary keys are not supported. Please use a single primary key .
        """
    end
  end
end
