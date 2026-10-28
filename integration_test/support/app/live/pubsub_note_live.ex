defmodule Backpex.Test.PubSubNoteLive do
  @moduledoc "Notes with a `pubsub` option. The test helper starts its PubSub server `Backpex.Test.OptionsPubSub`."
  use Backpex.Test.OptionsNoteLive, pubsub: [server: Backpex.Test.OptionsPubSub, topic: "options-notes"]
end
