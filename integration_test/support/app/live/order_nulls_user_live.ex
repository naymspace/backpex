defmodule Backpex.Test.OrderNullsUserLive do
  @moduledoc """
  Builds LiveResources on users that differ only in their `order_nulls` option, e.g.
  `use Backpex.Test.OrderNullsUserLive, order_nulls: :first`. `age` and `avatar` are nullable; `avatar` overrides the
  option of the LiveResource with its own `order_nulls: :last`.
  """
  defmacro __using__(opts) do
    quote do
      use Backpex.LiveResource,
          [
            adapter_config: [
              schema: Backpex.Test.User,
              repo: Backpex.Test.Repo,
              update_changeset: &Backpex.Test.User.changeset/3,
              create_changeset: &Backpex.Test.User.changeset/3
            ]
          ] ++ unquote(opts)

      @impl Backpex.LiveResource
      def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

      @impl Backpex.LiveResource
      def singular_name, do: "User"

      @impl Backpex.LiveResource
      def plural_name, do: "Users"

      @impl Backpex.LiveResource
      def fields do
        [
          username: %{module: Backpex.Fields.Text, label: "Username"},
          age: %{module: Backpex.Fields.Number, label: "Age"},
          avatar: %{module: Backpex.Fields.Text, label: "Avatar", order_nulls: :last}
        ]
      end
    end
  end
end

defmodule Backpex.Test.OrderNullsDefaultUserLive do
  @moduledoc "Users without an `order_nulls` option."
  use Backpex.Test.OrderNullsUserLive, []
end

defmodule Backpex.Test.OrderNullsFirstUserLive do
  @moduledoc "Users with `order_nulls: :first`."
  use Backpex.Test.OrderNullsUserLive, order_nulls: :first
end

defmodule Backpex.Test.OrderNullsLastUserLive do
  @moduledoc "Users with `order_nulls: :last`."
  use Backpex.Test.OrderNullsUserLive, order_nulls: :last
end

defmodule Backpex.Test.OrderNullsSmallestUserLive do
  @moduledoc "Users with `order_nulls: :smallest`."
  use Backpex.Test.OrderNullsUserLive, order_nulls: :smallest
end
