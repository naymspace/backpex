defmodule Backpex.Test.RecordingNoteLive do
  @moduledoc "Notes with `adapter: Backpex.Test.RecordingAdapter`, which reports every adapter call."
  use Backpex.Test.OptionsNoteLive, adapter: Backpex.Test.RecordingAdapter
end
