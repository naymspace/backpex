defmodule Backpex.Ecto.EctoUtilsTest do
  use ExUnit.Case, async: true

  alias Backpex.Ecto.EctoUtils

  defmodule TestSchema do
    use Ecto.Schema

    schema "test_schema" do
      field :name, :string
    end
  end

  defmodule TestSchemaWithoutPK do
    use Ecto.Schema
    @primary_key false
    schema "test_schema_without_pk" do
      field :name, :string
    end
  end

  defmodule TestSchemaWithCompoundPK do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    schema "test_schema_with_compound_pk" do
      field :other_id, :binary_id, primary_key: true
      field :name, :string
    end
  end

  describe "get_primary_key_field/1" do
    test "returns primary key for Ecto.Changeset" do
      changeset = Ecto.Changeset.change(%TestSchema{})
      assert EctoUtils.get_primary_key_field(changeset) == :id
    end

    test "returns primary key for struct" do
      assert EctoUtils.get_primary_key_field(%TestSchema{}) == :id
    end

    test "returns primary key for module" do
      assert EctoUtils.get_primary_key_field(TestSchema) == :id
    end

    test "returns primary key for schema with __schema__ function" do
      schema = %{__schema__: &TestSchema.__schema__/1}
      assert EctoUtils.get_primary_key_field(schema) == :id
    end

    test "raises error when no primary key is defined" do
      assert_raise ArgumentError, ~r/No primary key found/, fn ->
        EctoUtils.get_primary_key_field(TestSchemaWithoutPK)
      end
    end

    test "raises error for compound primary keys" do
      assert_raise ArgumentError, ~r/Compound primary keys are not supported/, fn ->
        EctoUtils.get_primary_key_field(TestSchemaWithCompoundPK)
      end
    end
  end
end
