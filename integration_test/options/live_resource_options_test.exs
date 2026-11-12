defmodule Backpex.Integration.Options.LiveResourceOptionsTest do
  @moduledoc """
  Checks the `fluid?` and `on_mount` options of a LiveResource, through `Backpex.Test.FluidNoteLive` and the
  LiveResources of `Backpex.Test.OnMountHook`. `Backpex.Test.NoteLive` sets neither.
  """
  use Backpex.ConnCase, async: true

  setup do
    %{note: insert(:note, title: "A note")}
  end

  describe "fluid?" do
    test "removes the maximum width of the content on every view", %{conn: conn, note: note} do
      for path <- [
            ~p"/admin/fluid-notes",
            ~p"/admin/fluid-notes/new",
            ~p"/admin/fluid-notes/#{note.id}/show",
            ~p"/admin/fluid-notes/#{note.id}/edit"
          ] do
        conn
        |> visit(path)
        |> assert_has("main > div.mx-auto")
        |> refute_has("main > div.max-w-7xl")
      end
    end

    test "limits the width of the content by default", %{conn: conn, note: note} do
      for path <- [~p"/admin/notes", ~p"/admin/notes/new", ~p"/admin/notes/#{note.id}/show"] do
        conn
        |> visit(path)
        |> assert_has("main > div.mx-auto.max-w-7xl")
      end
    end
  end

  describe "on_mount" do
    # {path, LiveResource, arguments the hook receives in order}
    for {path, live_resource, arguments} <- [
          {"/admin/on-mount-module-notes", Backpex.Test.OnMountModuleNoteLive, [:default]},
          {"/admin/on-mount-tuple-notes", Backpex.Test.OnMountTupleNoteLive, [:tuple]},
          {"/admin/on-mount-list-notes", Backpex.Test.OnMountListNoteLive, [:default, :second]}
        ] do
      @path path
      @live_resource live_resource
      @arguments arguments

      test "#{inspect(arguments)} runs on mount of the index, show and form views of #{inspect(live_resource)}",
           %{conn: conn, note: note} do
        for {view, path} <- [
              {Index, @path},
              {Show, "#{@path}/#{note.id}/show"},
              {Form, "#{@path}/new"},
              {Form, "#{@path}/#{note.id}/edit"}
            ] do
          view = Module.safe_concat(@live_resource, view)
          expected = Enum.map_join(@arguments, "; ", &"#{inspect(&1)} hook ran on #{inspect(view)}")

          conn
          |> visit(path)
          |> assert_has("#flash-info > div > div", text: expected, exact: true)
        end
      end
    end

    test "runs no hook without the option", %{conn: conn} do
      conn
      |> visit(~p"/admin/notes")
      |> refute_has("#flash-info")
    end
  end
end
