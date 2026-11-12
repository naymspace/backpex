defmodule Backpex.Test.OptionsNoteLive do
  @moduledoc """
  Builds LiveResources on notes that differ only in the options given to `use Backpex.LiveResource`, e.g.
  `use Backpex.Test.OptionsNoteLive, fluid?: true`. They render the title of a note.
  """
  defmacro __using__(opts) do
    quote do
      use Backpex.LiveResource,
          [
            adapter_config: [
              schema: Backpex.Test.Note,
              repo: Backpex.Test.Repo,
              update_changeset: &Backpex.Test.Note.changeset/3,
              create_changeset: &Backpex.Test.Note.changeset/3
            ]
          ] ++ unquote(opts)

      @impl Backpex.LiveResource
      def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

      @impl Backpex.LiveResource
      def singular_name, do: "Note"

      @impl Backpex.LiveResource
      def plural_name, do: "Notes"

      @impl Backpex.LiveResource
      def fields, do: [title: %{module: Backpex.Fields.Text, label: "Title"}]
    end
  end
end
