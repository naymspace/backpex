defmodule Backpex.Fields.DateTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.Date, as: DateField

  describe "render_value/1" do
    test "renders an empty value as a dash without calling the format function" do
      format = fn _date -> flunk("format function called") end

      assert render_value(nil, format) =~ "—"
    end

    test "renders an empty value as a dash with a format string" do
      assert render_value(nil, "%d.%m.%Y") =~ "—"
    end

    test "formats a value with the format function" do
      assert render_value(~D[2024-10-13], &Calendar.strftime(&1, "%d.%m.%Y")) =~ "13.10.2024"
    end

    test "formats a value with the format string" do
      assert render_value(~D[2024-10-13], "%d.%m.%Y") =~ "13.10.2024"
    end
  end

  defp render_value(value, format) do
    render_component(&DateField.render_value/1,
      value: value,
      field_options: %{module: DateField, label: "Date", format: format},
      live_action: :index
    )
  end
end
