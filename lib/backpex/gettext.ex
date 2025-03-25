defmodule Backpex.Gettext do
  @moduledoc """
  This module is mainly used to call gettext `*_noop` functions in order to automatically extract messages and create a `priv/gettext/backpex.pot` file.
  """
  use Gettext.Backend, otp_app: :backpex
end
