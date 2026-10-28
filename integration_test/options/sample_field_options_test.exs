defmodule Backpex.Integration.Options.SampleFieldOptionsTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest,
    only: [file_input: 4, form: 2, preflight_upload: 1, put_submitter: 2, render: 1, render_submit: 2, render_upload: 2]

  alias Backpex.Test.Sample

  # `Backpex.Test.SampleFieldOptionsLive` sets the options, while `Backpex.Test.SampleLive` leaves them at their
  # defaults.

  @file_entry %{name: "notes.txt", content: "notes", type: "text/plain"}

  describe "readonly of Backpex.Fields.Checkgroup" do
    test "disables the checkboxes and keeps the stored value on save", %{conn: conn} do
      sample = insert(:sample, text: "Before", checkgroup: ["read"])

      conn
      |> visit(~p"/admin/sample-field-options/#{sample.id}/edit")
      |> assert_has("input[type=checkbox][value=read][checked][disabled]")
      |> assert_has("input[type=checkbox][value=write][disabled]")
      # A crafted client can still send values for the disabled checkboxes.
      |> save(%{text: "After", checkgroup: ["write"]})

      assert %Sample{text: "After", checkgroup: ["read"]} = Repo.get!(Sample, sample.id)
    end

    test "is false by default", %{conn: conn} do
      sample = insert(:sample, text: "Before", checkgroup: ["read"])

      conn
      |> visit(~p"/admin/samples/#{sample.id}/edit")
      |> assert_has("input[type=checkbox][value=read][checked]")
      |> refute_has("input[type=checkbox][disabled]")
      |> save(%{checkgroup: ["write"]})

      assert %Sample{checkgroup: ["write"]} = Repo.get!(Sample, sample.id)
    end
  end

  describe "external of Backpex.Fields.Upload" do
    test "gives the client the metadata of the presign function", %{conn: conn} do
      conn
      |> visit(~p"/admin/sample-field-options/new")
      |> unwrap(fn view ->
        assert {:ok, %{entries: entries}} = view |> upload_input() |> preflight_upload()

        assert [%{uploader: "TestStorage", key: "samples/notes.txt", url: "https://storage.example/samples/notes.txt"}] =
                 Map.values(entries)

        render(view)
      end)
    end

    test "is not used by default", %{conn: conn} do
      conn
      |> visit(~p"/admin/samples/new")
      |> unwrap(fn view ->
        assert {:ok, %{entries: entries}} = view |> upload_input() |> preflight_upload()
        # Without `external`, each entry gets a token to upload its chunks to the LiveView.
        assert [token] = Map.values(entries)
        assert is_binary(token)

        render(view)
      end)
    end

    # `consume_upload/4` of the fixture only accepts the metadata of the presign function.
    test "consumes the upload with the metadata of the presign function", %{conn: conn} do
      conn
      |> visit(~p"/admin/sample-field-options/new")
      |> fill_in("Text", with: "Sample")
      |> unwrap(fn view ->
        view |> upload_input() |> render_upload("notes.txt")
        render(view)
      end)
      |> save(%{})

      assert [%Sample{text: "Sample", upload: "samples/notes.txt"}] = Repo.all(Sample)
    end
  end

  defp upload_input(view), do: file_input(view, "#resource-form", :upload, [@file_entry])

  defp save(session, params) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(%{change: params})
    end)
  end
end
