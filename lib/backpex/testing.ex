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

          assert_redirect(view, Testing.path(Router, PostLive, :index))
        end
      end

  `Phoenix.LiveViewTest` needs the `lazy_html` package in your test dependencies.
  """

  import Phoenix.LiveViewTest

  alias Backpex.LiveResource
  alias Backpex.Router

  @doc """
  Returns the path of a view of `live_resource` in `router`.

  `action` is one of `:index`, `:new`, `:show`, `:edit` and `:resource_action`. The `:show` and `:edit` views take the
  item or its primary value, the `:resource_action` view the key of the resource action. `params` are the params of the
  route, e.g. a tenant for routes under `/:tenant/admin`.

  ## Examples

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.PostLive, :index)
      #=> "/admin/posts"

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.PostLive, :edit, post)
      #=> "/admin/posts/1/edit"

      Backpex.Testing.path(MyAppWeb.Router, MyAppWeb.UserLive, :resource_action, :invite)
      #=> "/admin/users/invite/resource-action"
  """
  def path(router, live_resource, action, item_or_key \\ nil, params \\ %{})

  def path(router, live_resource, action, nil, params) when action in [:index, :new] do
    Router.get_path(%{router: router}, live_resource, params, action)
  end

  def path(router, live_resource, action, item_or_id, params) when action in [:show, :edit] do
    Router.get_path(%{router: router}, live_resource, params, action, primary_value(item_or_id, live_resource), %{})
  end

  def path(router, live_resource, :resource_action, key, params) when is_atom(key) do
    Router.get_path(%{router: router}, live_resource, params, :resource_action, Atom.to_string(key), %{})
  end

  @doc """
  Selects the row of `item` on the index view, like a click on its checkbox. Bulk item actions apply to the selected
  rows.
  """
  def select_item(view, item) do
    view
    |> element(~s|input[id="select-input-#{primary_value(item, view)}"]|)
    |> render_click()

    view
  end

  @doc """
  Clicks the item action `key`.

  With an `item`, it clicks the action in the row of the item on the index view. Without one, it clicks the action
  above the table of the index view, which applies to the selected rows, or the action on the show view.
  """
  def click_item_action(view, key, item \\ nil)

  def click_item_action(view, key, nil) do
    view
    |> element(
      ~s|[id="item-action-#{key}"], button[phx-click="item-action"][phx-value-action-key="#{key}"]:not([phx-value-item-id])|
    )
    |> render_click()

    view
  end

  def click_item_action(view, key, item) do
    view
    |> element(~s|[id="item-action-#{key}-#{primary_value(item, view)}"]|)
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

  `submitter` is the value of the button that submits the form: `"save"` (default), `"continue"` for "Save & Continue
  editing" or the key of a custom form action.
  """
  def submit_form(view, params, submitter \\ "save") do
    view
    |> form("#resource-form", change: params)
    |> put_submitter(~s|button[value="#{submitter}"]|)
    |> render_submit()

    view
  end

  # The views of a LiveResource are the modules `Index`, `Form` and `Show` inside of it.
  defp primary_value(item, %Phoenix.LiveViewTest.View{module: module}) do
    live_resource = module |> Module.split() |> Enum.drop(-1) |> Module.concat()
    primary_value(item, live_resource)
  end

  defp primary_value(item, live_resource) when is_map(item), do: LiveResource.primary_value(item, live_resource)
  defp primary_value(id, _live_resource), do: id
end
