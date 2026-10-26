defmodule Backpex.Testing do
  @moduledoc """
  Helpers for testing your LiveResources with `Phoenix.LiveViewTest`.

  They find the views of a LiveResource in your router and the elements Backpex renders for items, item actions and
  forms, so your tests don't depend on the markup of Backpex.

      defmodule MyAppWeb.PostLiveTest do
        use MyAppWeb.ConnCase, async: true

        import Phoenix.LiveViewTest

        alias Backpex.Testing
        alias MyAppWeb.PostLive
        alias MyAppWeb.Router

        test "deletes a post", %{conn: conn} do
          post = insert(:post)
          {:ok, view, _html} = live(conn, Testing.path(Router, PostLive, :index))

          view
          |> Testing.click_item_action(:delete, post)
          |> Testing.confirm_item_action()

          refute Repo.get(Post, post.id)
        end

        test "updates a post", %{conn: conn} do
          post = insert(:post)
          {:ok, view, _html} = live(conn, Testing.path(Router, PostLive, :edit, post))

          Testing.submit_form(view, %{title: "Updated"})

          {path, _flash} = assert_redirect(view)
          assert path == Testing.path(Router, PostLive, :index)

          {:ok, _view, html} = live(conn, path)
          assert html =~ "Updated"
        end
      end

  The helpers take an item or its primary value. With an item, they read the primary value with the LiveResource of
  the view, so pass the primary value when you test a LiveView that isn't a view of a LiveResource.

  The helpers return the view, so you can pipe them, but not the result of the click or submit, so
  `Phoenix.LiveViewTest.follow_redirect/2` doesn't work with them. To follow a navigation to another view, get its path
  with `Phoenix.LiveViewTest.assert_redirect/1` and mount it with `Phoenix.LiveViewTest.live/2`. A patch stays in the
  view, so `Phoenix.LiveViewTest.assert_patch/1` is enough.

  `Phoenix.LiveViewTest` needs the `lazy_html` package in your test dependencies.
  """

  import Phoenix.LiveViewTest

  alias Backpex.LiveResource
  alias Backpex.Router

  @doc """
  Returns the path of a view of `live_resource` in `router`.

  `action` is one of `:index`, `:new`, `:show`, `:edit` and `:resource_action`. The `:show` and `:edit` views take the
  item or its primary value, the `:resource_action` view the key of the resource action. The `:index` and `:new` views
  can take the options as the fourth argument.

  ## Options

    * `:params` - the params of the route as a map or keyword list, e.g. a tenant for routes under `/:tenant/admin`.
      Keys and values are converted to strings.
    * `:query` - the query params of the path as a map or keyword list.

  ## Examples

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.PostLive, :index)
      #=> "/admin/posts"

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.PostLive, :index, query: [page: 2])
      #=> "/admin/posts?page=2"

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.PostLive, :edit, post)
      #=> "/admin/posts/1/edit"

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.PostLive, :show, post, params: [tenant: 42])
      #=> "/42/admin/posts/1/show"

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.UserLive, :resource_action, :invite)
      #=> "/admin/users/invite/resource-action"
  """
  def path(router, live_resource, action, item_or_key \\ nil, opts \\ [])

  def path(router, live_resource, action, opts, []) when action in [:index, :new] and is_list(opts) do
    path(router, live_resource, action, nil, opts)
  end

  def path(router, live_resource, action, nil, opts) when action in [:index, :new] do
    build_path(router, live_resource, action, nil, opts)
  end

  def path(router, live_resource, action, item_or_id, opts) when action in [:show, :edit] do
    build_path(router, live_resource, action, primary_value(item_or_id, live_resource), opts)
  end

  def path(router, live_resource, :resource_action, key, opts) when is_atom(key) and not is_nil(key) do
    build_path(router, live_resource, :resource_action, Atom.to_string(key), opts)
  end

  defp build_path(router, live_resource, action, id, opts) do
    opts = Keyword.validate!(opts, params: [], query: [])
    params = Map.new(opts[:params], fn {key, value} -> {to_string(key), to_string(value)} end)

    Router.get_path(%{router: router}, live_resource, params, action, id, opts[:query])
  end

  @doc """
  Selects the row of `item` on the index view, like a click on its checkbox. Bulk item actions apply to the selected
  rows. Does nothing if the row is already selected.
  """
  def select_item(view, item), do: toggle_item(view, item, false)

  @doc """
  Deselects the row of `item` on the index view, like a click on its checkbox. Does nothing if the row isn't selected.
  """
  def deselect_item(view, item), do: toggle_item(view, item, true)

  # Clicks the checkbox of the row only if its state is `selected?`, because a click toggles the selection.
  defp toggle_item(view, item, selected?) do
    selector = ~s|input[id="select-input-#{escape(primary_value(item, view))}"]|

    if has_element?(view, selector <> "[checked]") == selected? do
      view
      |> element(selector)
      |> render_click()
    end

    view
  end

  @doc """
  Clicks the item action `key`.

  With an `item`, it clicks the action in the row of the item on the index view. Without one, it clicks the action
  above the table of the index view, which applies to the selected rows, or the action on the show view.

  An item action with a link, like `:show` and `:edit`, navigates to another view. Get its path with
  `Phoenix.LiveViewTest.assert_redirect/1` and mount it with `Phoenix.LiveViewTest.live/2`:

      Testing.click_item_action(view, :show, post)
      {path, _flash} = assert_redirect(view)
      {:ok, view, _html} = live(conn, path)
  """
  def click_item_action(view, key, item \\ nil)

  def click_item_action(view, key, nil) do
    key = escape(key)

    view
    |> element(
      ~s|[id="item-action-#{key}"], button[phx-click="item-action"][phx-value-action-key="#{key}"]:not([phx-value-item-id])|
    )
    |> render_click()

    view
  end

  def click_item_action(view, key, item) do
    view
    |> element(~s|[id="item-action-#{escape(key)}-#{escape(primary_value(item, view))}"]|)
    |> render_click()

    view
  end

  @doc """
  Confirms the item action whose confirmation modal is open. `params` fill in the fields of the item action.
  """
  def confirm_item_action(view, params \\ %{}) do
    view
    |> form("#action-confirm-modal form", change: params)
    |> render_submit()

    view
  end

  @doc """
  Fills in the form of the new or edit view with `params` and saves it.

  `submitter` is the key of the form action that submits the form: `"save"` (default), `"continue"` for "Save &
  Continue editing" or the key of a custom form action.

  Saving navigates to the path of the form action. Get it with `Phoenix.LiveViewTest.assert_redirect/1` and mount it with
  `Phoenix.LiveViewTest.live/2`.
  """
  def submit_form(view, params, submitter \\ "save") do
    view
    |> form("#resource-form", change: params)
    |> put_submitter(~s|button[type="submit"][name="save-type"][value="#{escape(submitter)}"]|)
    |> render_submit()

    view
  end

  defp primary_value(item, %Phoenix.LiveViewTest.View{module: module}) when is_map(item) do
    case live_resource(module) do
      nil ->
        raise ArgumentError,
              "#{inspect(module)} is not a view of a LiveResource, so the primary value of the item can't be read. " <>
                "Pass the primary value instead of the item."

      live_resource ->
        primary_value(item, live_resource)
    end
  end

  defp primary_value(item, live_resource) when is_map(item) do
    case LiveResource.primary_value(item, live_resource) do
      nil -> raise ArgumentError, "the item has no primary value, got: #{inspect(item)}"
      value -> value
    end
  end

  defp primary_value(nil, _view_or_live_resource), do: raise(ArgumentError, "expected an item or its primary value")
  defp primary_value(id, _view_or_live_resource), do: id

  # The views of a LiveResource are the modules `Index`, `Form` and `Show` inside of it.
  defp live_resource(view_module) do
    live_resource = view_module |> Module.split() |> Enum.drop(-1) |> Module.safe_concat()

    if Code.ensure_loaded?(live_resource) and function_exported?(live_resource, :config, 1), do: live_resource
  rescue
    ArgumentError -> nil
  end

  # Escapes a value for a quoted string in a CSS selector.
  defp escape(value), do: value |> to_string() |> String.replace(["\\", "\""], &("\\" <> &1))
end
