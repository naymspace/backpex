defmodule Backpex.Fields.TimeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.Time, as: TimeField

  describe "render_value/1" do
    test "renders an empty value as a dash without calling the format function" do
      format = fn _time -> flunk("format function called") end

      assert render_value(nil, format) =~ "—"
    end

    test "renders an empty value as a dash with a format string" do
      assert render_value(nil, "%H:%M") =~ "—"
    end

    test "formats a value with the format function" do
      assert render_value(~T[14:30:00], &Calendar.strftime(&1, "%H:%M")) =~ "14:30"
    end

    test "formats a value with the format string" do
      assert render_value(~T[14:30:00], "%H:%M") =~ "14:30"
    end
  end

  defp render_value(value, format) do
    render_component(&TimeField.render_value/1,
      value: value,
      field_options: %{module: TimeField, label: "Time", format: format},
      live_action: :index
    )
  end
end
