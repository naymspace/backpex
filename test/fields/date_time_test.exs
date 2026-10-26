defmodule Backpex.Fields.DateTimeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.DateTime, as: DateTimeField

  describe "render_value/1" do
    test "renders an empty value as a dash without calling the format function" do
      format = fn _date_time -> flunk("format function called") end

      assert render_value(nil, format) =~ "—"
    end

    test "renders an empty value as a dash with a format string" do
      assert render_value(nil, "%d.%m.%Y %H:%M") =~ "—"
    end

    test "formats a value with the format function" do
      assert render_value(~U[2024-10-13 14:30:00Z], &Calendar.strftime(&1, "%d.%m.%Y %H:%M")) =~ "13.10.2024 14:30"
    end

    test "formats a value with the format string" do
      assert render_value(~U[2024-10-13 14:30:00Z], "%d.%m.%Y %H:%M") =~ "13.10.2024 14:30"
    end
  end

  defp render_value(value, format) do
    render_component(&DateTimeField.render_value/1,
      value: value,
      field_options: %{module: DateTimeField, label: "Date Time", format: format},
      live_action: :index
    )
  end
end
