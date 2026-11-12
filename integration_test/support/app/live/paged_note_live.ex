defmodule Backpex.Test.PagedNoteLive do
  @moduledoc "Notes with `per_page_options: [3, 6, 12]` and `per_page_default: 6` instead of the defaults."
  use Backpex.Test.OptionsNoteLive, per_page_options: [3, 6, 12], per_page_default: 6
end
