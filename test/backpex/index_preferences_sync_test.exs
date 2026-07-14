defmodule Backpex.LiveResource.IndexPreferencesSyncTest do
  use ExUnit.Case, async: true

  alias Backpex.LiveResource.Index
  alias Backpex.Preferences.Keys, as: PreferenceKeys
  alias Phoenix.LiveView.Socket

  # Minimal stand-ins for a generated LiveResource module — only the
  # `config(:persist)` call that `sync_preferences/2` consults.
  defmodule PersistedResource do
    def config(:persist), do: [:columns, :metrics]
  end

  defmodule UnpersistedResource do
    def config(:persist), do: []
  end

  defp socket(assigns) do
    %Socket{assigns: Map.merge(%{__changed__: %{}}, assigns)}
  end

  defp active_fields do
    [
      {:title, %{active: true, label: "Title"}},
      {:tags, %{active: true, label: "Tags"}}
    ]
  end

  describe "sync_preferences/2 for columns" do
    test "applies mirrored column visibility over the mount-time read" do
      socket = socket(%{live_resource: PersistedResource, active_fields: active_fields()})
      prefs = %{PreferenceKeys.columns(PersistedResource) => %{"tags" => false}}

      synced = Index.sync_preferences(socket, prefs)

      assert synced.assigns.active_fields == [
               {:title, %{active: true, label: "Title"}},
               {:tags, %{active: false, label: "Tags"}}
             ]
    end

    test "ignores unknown field names and non-boolean values" do
      socket = socket(%{live_resource: PersistedResource, active_fields: active_fields()})

      prefs = %{
        PreferenceKeys.columns(PersistedResource) => %{"bogus" => false, "title" => "nope"}
      }

      synced = Index.sync_preferences(socket, prefs)

      assert synced.assigns.active_fields == active_fields()
    end

    test "no-ops when column persistence is disabled for the resource" do
      socket = socket(%{live_resource: UnpersistedResource, active_fields: active_fields()})
      prefs = %{PreferenceKeys.columns(UnpersistedResource) => %{"tags" => false}}

      synced = Index.sync_preferences(socket, prefs)

      assert synced.assigns.active_fields == active_fields()
    end

    test "no-ops when the mirror carries no entry for this resource" do
      socket = socket(%{live_resource: PersistedResource, active_fields: active_fields()})

      synced = Index.sync_preferences(socket, %{"global.sidebar_open" => false})

      assert synced.assigns.active_fields == active_fields()
    end
  end

  describe "sync_preferences/2 for metrics" do
    test "leaves the socket untouched when the mirrored visibility matches" do
      socket =
        socket(%{
          live_resource: PersistedResource,
          active_fields: active_fields(),
          metric_visibility: %{to_string(PersistedResource) => false}
        })

      prefs = %{PreferenceKeys.metrics_visible(PersistedResource) => false}

      synced = Index.sync_preferences(socket, prefs)

      assert synced.assigns.metric_visibility == %{to_string(PersistedResource) => false}
    end

    test "ignores non-boolean mirrored visibility" do
      socket =
        socket(%{
          live_resource: PersistedResource,
          active_fields: active_fields(),
          metric_visibility: %{to_string(PersistedResource) => true}
        })

      prefs = %{PreferenceKeys.metrics_visible(PersistedResource) => "nope"}

      synced = Index.sync_preferences(socket, prefs)

      assert synced.assigns.metric_visibility == %{to_string(PersistedResource) => true}
    end

    test "no-ops when metrics persistence is disabled for the resource" do
      socket =
        socket(%{
          live_resource: UnpersistedResource,
          active_fields: active_fields(),
          metric_visibility: %{to_string(UnpersistedResource) => true}
        })

      prefs = %{PreferenceKeys.metrics_visible(UnpersistedResource) => false}

      synced = Index.sync_preferences(socket, prefs)

      assert synced.assigns.metric_visibility == %{to_string(UnpersistedResource) => true}
    end
  end

  describe "sync_preferences/2 on non-index sockets" do
    test "no-ops for LiveViews without index assigns (Show/Form)" do
      socket = socket(%{live_resource: PersistedResource})
      prefs = %{PreferenceKeys.columns(PersistedResource) => %{"tags" => false}}

      assert Index.sync_preferences(socket, prefs) == socket
    end

    test "no-ops on a malformed (non-map) payload" do
      socket = socket(%{live_resource: PersistedResource, active_fields: active_fields()})

      assert Index.sync_preferences(socket, "junk") == socket
    end
  end
end
