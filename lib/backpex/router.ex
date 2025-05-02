defmodule Backpex.Router do
  @moduledoc """
  Provides LiveView routing for Backpex resources.
  """

  alias Plug.Conn.Query

  @doc """
  Defines "RESTful" routes for a Backpex resource.

  ## Options

    * `:only` - List of actions to generate routes for, for example: `[:index, :show]`.
    * `:except` - List of actions to exclude generated routes from, for example: `[:edit]`.

  ## Example

      defmodule MyAppWeb.Router
        import Backpex.Router

        scope "/admin", MyAppWeb do
          pipe_through :browser

          live_session :default, on_mount: Backpex.InitAssigns do
            live_resources("/users", UserLive, only: [:index])
          end
        end
      end
  """
  defmacro live_resources(path, live_resource, options \\ []) do
    alias Backpex.Router

    only = Keyword.get(options, :only)
    except = Keyword.get(options, :except)

    quote do
      actions =
        [:index, :new, :edit, :show]
        |> Router.filter_actions(unquote(only), unquote(except))

      path = unquote(path)
      live_resource = unquote(live_resource)

      if Enum.member?(actions, :index), do: live("#{path}/", String.to_existing_atom("#{live_resource}.Index"), :index)
      if Enum.member?(actions, :new), do: live("#{path}/new", String.to_existing_atom("#{live_resource}.Form"), :new)

      if Enum.member?(actions, :edit),
        do: live("#{path}/:backpex_id/edit", String.to_existing_atom("#{live_resource}.Form"), :edit)

      if Enum.member?(actions, :show),
        do: live("#{path}/:backpex_id/show", String.to_existing_atom("#{live_resource}.Show"), :show)

      resource_module = Phoenix.Router.scoped_alias(__MODULE__, live_resource)

      if Router.has_resource_actions?(__MODULE__, live_resource) do
        live(
          "#{path}/:backpex_id/resource-action",
          String.to_existing_atom("#{live_resource}.Index"),
          :resource_action
        )
      end
    end
  end

  def has_resource_actions?(module, live_resource) do
    resource_module = Phoenix.Router.scoped_alias(module, live_resource)
    Enum.count(resource_module.resource_actions()) > 0
  end

  defmacro backpex_routes do
    quote do
      scope "/", alias: false, as: false do
        post "/backpex_cookies", Backpex.CookieController, :update
      end
    end
  end

  @doc """
  Checks whether the to path is the same as the current path

  ## Examples

      iex> Backpex.Router.active?(URI.new!("https://example.com/admin/events"), "/admin/events")
      true
      iex> Backpex.Router.active?(URI.new!("https://example.com/admin/events"), "/admin/users")
      false
  """
  def active?(current_path, to_path) do
    %{path: path} = URI.parse(current_path)

    case {path, to_path} do
      {nil, _to} -> false
      {path, "/" = to} -> String.equivalent?(path, to)
      {path, to} -> String.starts_with?(path, to)
    end
  end

  @doc """
  Filters `actions` based on `only` and `except` parameters.

  ## Examples

      iex> Backpex.Router.filter_actions([:index, :edit, :show], [:index], nil)
      [:index]
      iex> Backpex.Router.filter_actions([:index, :edit, :show], nil, [:index])
      [:edit, :show]
      iex> Backpex.Router.filter_actions([:index, :edit, :show], nil, nil)
      [:index, :edit, :show]
      iex> Backpex.Router.filter_actions([:index, :edit, :show], [], [])
      [:index, :edit, :show]
  """
  def filter_actions(actions, only, except) do
    actions
    |> Enum.filter(fn item ->
      member?(only, item, true) and not member?(except, item, false)
    end)
  end

  @doc """
  Checks whether `item` is member of `list` and returns `default` value if list is `nil` or empty.

  ## Examples

      iex> Backpex.Router.member?([:index], :index, true)
      true
      iex> Backpex.Router.member?([:edit], :index, true)
      false
      iex> Backpex.Router.member?([], :index, true)
      true
      iex> Backpex.Router.member?(nil, :index, true)
      true
  """
  def member?(nil, _item, default), do: default
  def member?([], _item, default), do: default
  def member?(list, item, _default), do: Enum.member?(list, item)

  @doc """
  Finds the raw path by the given socket and module and puts the path params into the raw path.
  """
  def get_path(socket, module, params, action, params_or_item \\ %{}) do
    route_path = get_route_path(socket, module, action)

    id_field = module.config(:primary_key)

    if Map.has_key?(params_or_item, id_field) do
      id = params_or_item |> Map.get(id_field) |> to_string() |> URI.encode_www_form()

      put_route_params(route_path, Map.put(params, "backpex_id", maybe_to_string(id)))
    else
      query_params = Query.encode(params_or_item)
      put_route_params(route_path, params) |> maybe_put_query_params(query_params)
    end
  end

  def get_path(socket, module, params, action, id_or_instance, query_params) do
    id_field = module.config(:primary_key)

    id_serializable =
      if is_map(id_or_instance) and Map.has_key?(id_or_instance, id_field),
        do: Map.get(id_or_instance, id_field),
        else: id_or_instance

    route_path = get_route_path(socket, module, action)
    query_params = Query.encode(query_params)

    put_route_params(route_path, Map.put(params, "backpex_id", maybe_to_string(id_serializable)))
    |> maybe_put_query_params(query_params)
  end

  defp maybe_put_query_params(path, "" = _encoded_query_params), do: path
  defp maybe_put_query_params(path, encoded_query_params), do: path <> "?" <> encoded_query_params

  defp get_route_path(socket, module, action) do
    action_module = action_module(module, action)

    route =
      Enum.find(Map.get(socket, :router).__routes__(), fn element ->
        element[:metadata][:log_module] == action_module and element[:plug_opts] == action
      end)

    case route do
      %{path: path} ->
        path

      nil ->
        raise ArgumentError, """
        Could not find route for #{inspect(action_module)} with action #{inspect(action)}.
        Make sure you have defined the route in your router.
        """
    end
  end

  defp action_module(module, :resource_action), do: action_module(module, :index)

  defp action_module(module, action) when action in [:edit, :new], do: action_module(module, :form)

  defp action_module(module, action) do
    action
    |> to_string()
    |> String.capitalize()
    |> then(fn a -> to_string(module) <> "." <> a end)
    |> String.to_existing_atom()
  end

  @doc """
  Replace path params with actual params

  ## Examples

      iex> Backpex.Router.put_route_params("/:param1/events/:param2/show", %{"param1" => "123", "param2" => "xyz", "test" => "abcdef"})
      "/123/events/xyz/show"
      iex> Backpex.Router.put_route_params("/:param1/events/:id/edit", %{"param1" => "123", "id" => "xyz"})
      "/123/events/xyz/edit"
      iex> Backpex.Router.put_route_params("/:param1/events/:id/edit", %{"param1" => "123", "id" => "hällö / world"})
      "/123/events/h%C3%A4ll%C3%B6+%2F+world/edit"
      iex> Backpex.Router.put_route_params("/events", %{"param1" => "123", "param2" => "xyz"})
      "/events"
      iex> Backpex.Router.put_route_params("/events", %{})
      "/events"
      iex> Backpex.Router.put_route_params("/:id/users", %{})
      ** (ArgumentError) Cannot build route '/:id/users' because required parameter 'id' is missing in the list of params.
  """
  def put_route_params(route, params) do
    route
    |> String.split("/")
    |> Enum.reduce("", fn
      "", acc ->
        acc

      ":" <> param, acc ->
        case Map.fetch(params, param) do
          {:ok, value} ->
            acc <> "/#{URI.encode_www_form(value)}"

          :error ->
            raise ArgumentError,
                  "Cannot build route '#{route}' because required parameter '#{param}' is missing in the list of params."
        end

        acc <> "/#{URI.encode_www_form(params[param])}"

      path, acc ->
        acc <> "/#{path}"
    end)
  end

  @doc """
  Finds the cookie path by the given socket.
  """
  def cookie_path(socket) do
    route =
      Enum.find(Map.get(socket, :router).__routes__(), fn element ->
        element[:plug] == Backpex.CookieController and element[:plug_opts] == :update
      end)

    case route do
      %{path: path} ->
        path

      nil ->
        raise ArgumentError, """
        Could not find backpex_cookies route. Make sure you have added backpex_routes to your router.

        See: https://hexdocs.pm/backpex/installation.html#add-backpex-routes
        """
    end
  end

  defp maybe_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_to_string(value), do: value
end
