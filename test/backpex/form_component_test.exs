defmodule Backpex.FormComponentTest do
  use ExUnit.Case, async: true

  alias Backpex.FormComponent
  alias Phoenix.LiveView.Socket

  # A LiveResource whose adapter reports the params of a changeset to the test instead of building one from a schema.
  defmodule ChangeLive do
    def config(:adapter), do: __MODULE__
    def translate({msg, _opts}), do: msg

    def change(_item, attrs, _fields, _assigns, _live_resource, _opts) do
      send(self(), {:change, attrs})
      Ecto.Changeset.change({%{}, %{images: {:array, :string}, docs: {:array, :string}}})
    end
  end

  describe "handle_event/3" do
    test "ignores events it does not handle" do
      fields = [title: %{module: Backpex.Fields.Text, label: "Title"}]
      socket = Phoenix.Component.assign(%Socket{}, :fields, fields)

      assert FormComponent.handle_event("unknown", %{}, socket) == {:noreply, socket}
      assert FormComponent.handle_event("cancel-entry", %{}, socket) == {:noreply, socket}
    end

    test "drops the changes of readonly fields on a save without params" do
      upload_options = %{
        module: Backpex.Fields.Upload,
        accept: :any,
        max_entries: 1,
        list_existing_files: fn _item -> [] end,
        put_upload_change: fn _socket, params, _item, _uploaded_entries, _removed_entries, _action ->
          Map.merge(params, %{"images" => ["new.png"], "docs" => ["new.pdf"]})
        end
      }

      fields = [images: Map.put(upload_options, :readonly, true), docs: upload_options]

      # The editable field has a refused file, so the save stops before it reaches the database.
      socket =
        %Socket{}
        |> Phoenix.Component.assign(fields: fields, item: %{}, live_resource: ChangeLive, live_action: :edit)
        |> Phoenix.Component.assign(removed_uploads: [])
        |> Phoenix.LiveView.allow_upload(:docs, accept: :any, max_entries: 1)

      socket = Phoenix.Component.update(socket, :uploads, &put_in(&1.docs.errors, [{&1.docs.ref, :too_many_files}]))

      FormComponent.handle_event("save", %{}, socket)

      assert_received {:change, attrs}
      assert attrs["docs"] == ["new.pdf"]
      refute Map.has_key?(attrs, "images")
    end
  end
end
