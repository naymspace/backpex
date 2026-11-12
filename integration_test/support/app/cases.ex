defmodule Backpex.DataCase do
  @moduledoc """
  The case for tests that use the database of the test app. Every test runs in its own sandbox transaction, so these
  tests can be `async: true`.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Backpex.DataCase
      import Backpex.Test.EctoFactory
      import Ecto.Query

      alias Backpex.Test.Repo
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  @doc "Checks out a sandbox connection that is shared with every process unless the test is async."
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Backpex.Test.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  Counts the queries on the table `source` that `fun` runs. Only queries of the test process and the processes it started,
  like a LiveView under test, are counted, so async tests don't see the queries of other tests.
  """
  def count_queries(source, fun) do
    handler_id = {__MODULE__, make_ref()}
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:backpex, :test, :repo, :query],
      fn _event, _measurements, %{source: query_source}, _config ->
        if query_source == source and test_pid in [self() | Process.get(:"$callers", [])] do
          send(test_pid, {:query, handler_id})
        end
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    count_messages({:query, handler_id})
  end

  defp count_messages(message, count \\ 0) do
    receive do
      ^message -> count_messages(message, count + 1)
    after
      0 -> count
    end
  end
end

defmodule Backpex.ConnCase do
  @moduledoc """
  The case for tests that drive the LiveResources of the test app with `PhoenixTest` and `Phoenix.LiveViewTest`.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.VerifiedRoutes, endpoint: Backpex.Test.Endpoint, router: Backpex.Test.Router

      import Backpex.ConnCase
      import Backpex.DataCase, only: [count_queries: 2]
      import Backpex.Test.EctoFactory
      import Phoenix.ConnTest
      import PhoenixTest
      import Plug.Conn

      alias Backpex.Test.Repo

      @endpoint Backpex.Test.Endpoint
    end
  end

  setup tags do
    Backpex.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Asserts that the table body `tbody` has one row per text, in this order, each with a cell of exactly that text.
  """
  def assert_rows(session, tbody, texts) do
    session = PhoenixTest.assert_has(session, "#{tbody} tr", count: length(texts))

    texts
    |> Enum.with_index(1)
    |> Enum.reduce(session, fn {text, index}, session ->
      PhoenixTest.assert_has(session, "#{tbody} tr:nth-child(#{index}) td", text: text, exact: true)
    end)
  end
end
