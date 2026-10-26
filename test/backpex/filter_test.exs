defmodule Backpex.FilterTest do
  use ExUnit.Case, async: true

  alias Backpex.Filter
  alias Backpex.Filters.Select

  defmodule StatusSelect do
    @moduledoc false
    use Select

    @impl Backpex.Filter
    def label, do: "Status"

    @impl Backpex.Filter
    def can?(assigns), do: Map.get(assigns, :admin?, false)

    @impl Select
    def prompt, do: "Any status"

    @impl Select
    def options(_assigns), do: [{"Open", "open"}]
  end

  defmodule MinFilter do
    @moduledoc false
    use Backpex.Filter, config_schema: [min: [type: :integer, default: 0]]

    @impl Backpex.Filter
    def type(_filter, _assigns), do: :integer

    @impl Backpex.Filter
    def changeset(changeset, {field, config}, _assigns) do
      Ecto.Changeset.validate_number(changeset, field, greater_than_or_equal_to: config.min)
    end

    @impl Backpex.Filter
    def condition({field, config}, value, _assigns), do: {:>=, field, max(value, config.min)}

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  describe "use Backpex.Filter" do
    test "refuses to compile a filter that still defines query/4, also on top of a built-in filter" do
      for {name, using} <- [QueryFilter: Backpex.Filter, QuerySelect: Select] do
        code = """
        defmodule Backpex.FilterTest.#{name} do
          use #{inspect(using)}

          def query(query, _field, _value, _assigns), do: query
        end
        """

        assert_raise CompileError, ~r/defines query\/4, but filters no longer build queries/, fn ->
          Code.compile_string(code)
        end
      end
    end

    test "refuses to compile a filter that still defines type/1 or validate/2" do
      for {name, definition, message} <- [
            {TypeFilter, "def type(_assigns), do: :string", ~r/defines type\/1, .* Implement type\/2 instead/},
            {ValidateFilter, "def validate(value, _assigns), do: {:ok, value}", ~r/defines validate\/2/}
          ] do
        code = """
        defmodule Backpex.FilterTest.#{inspect(name)} do
          use Backpex.Filter

          #{definition}
        end
        """

        assert_raise CompileError, message, fn -> Code.compile_string(code) end
      end
    end

    test "validates a value with the options of the filter" do
      filter = Filter.validate_config!({:count, %{module: MinFilter, label: "Count", min: 5}}, __MODULE__)

      assert MinFilter.validate(filter, "7", %{}) == {:ok, 7}
      assert {:error, [value: {_message, _opts}]} = MinFilter.validate(filter, "3", %{})
      assert {:error, [value: {"is invalid", _opts}]} = MinFilter.validate(filter, "seven", %{})
    end
  end

  describe "validate_config!/2" do
    test "validates the general options and the options of the filter module" do
      options = [{"Open", "open"}]
      config = %{module: Select, label: "Status", options: options, default: "open"}

      assert Filter.validate_config!({:status, config}, __MODULE__) == {:status, config}
    end

    test "puts the defaults of the options of the filter module" do
      assert {:count, %{min: 0}} = Filter.validate_config!({:count, %{module: MinFilter, label: "Count"}}, __MODULE__)
    end

    test "takes the callbacks of a reusable filter module as the defaults of its options" do
      {:status, config} = Filter.validate_config!({:status, %{module: StatusSelect}}, __MODULE__)

      assert config.options.(%{}) == [{"Open", "open"}]
      assert config.prompt.(%{}) == "Any status"

      assert {:status, %{options: [{"Closed", "closed"}], prompt: "Closed?"}} =
               Filter.validate_config!(
                 {:status, %{module: StatusSelect, options: [{"Closed", "closed"}], prompt: "Closed?"}},
                 __MODULE__
               )
    end

    test "raises on unknown and invalid options" do
      assert_raise ArgumentError, ~r/filter "status" in "Backpex.FilterTest".*unknown options \[:optons\]/s, fn ->
        Filter.validate_config!({:status, %{module: Select, label: "Status", optons: []}}, __MODULE__)
      end

      assert_raise ArgumentError, ~r/required :options option not found/, fn ->
        Filter.validate_config!({:status, %{module: Select, label: "Status"}}, __MODULE__)
      end

      assert_raise ArgumentError, ~r/invalid value for :type option/, fn ->
        Filter.validate_config!({:likes, %{module: Backpex.Filters.Range, label: "Likes", type: :text}}, __MODULE__)
      end
    end

    test "raises if neither the options nor the module define a label" do
      assert_raise ArgumentError, ~r/required :label option not found/, fn ->
        Filter.validate_config!({:likes, %{module: Backpex.Filters.Range, type: :number}}, __MODULE__)
      end
    end
  end

  describe "label/1" do
    test "returns the label option or the label of the module" do
      assert Filter.label({:status, %{module: StatusSelect, label: "State"}}) == "State"
      assert Filter.label({:status, %{module: StatusSelect}}) == "Status"
    end
  end

  describe "can?/2" do
    test "requires the can? option and the can? callback of the module to allow the filter" do
      filter = {:status, %{module: StatusSelect}}
      only_owners = {:status, %{module: StatusSelect, can?: &Map.get(&1, :owner?, false)}}

      assert Filter.can?(filter, %{admin?: true})
      refute Filter.can?(filter, %{admin?: false})
      assert Filter.can?(only_owners, %{admin?: true, owner?: true})
      refute Filter.can?(only_owners, %{admin?: true, owner?: false})
      refute Filter.can?(only_owners, %{admin?: false, owner?: true})
    end
  end

  describe "to_condition/3" do
    test "returns the condition of the filter module" do
      filter = {:count, %{module: MinFilter, min: 5}}

      assert Filter.to_condition(filter, 3, %{}) == {:>=, :count, 5}
    end

    test "returns the result of the condition option instead" do
      condition = fn {field, config}, value, assigns ->
        {:and, [{:==, field, value}, {:==, config.min, assigns.min}]}
      end

      filter = {:count, %{module: MinFilter, min: 5, condition: condition}}

      assert Filter.to_condition(filter, 3, %{min: 1}) == {:and, [{:==, :count, 3}, {:==, 5, 1}]}
    end
  end
end
