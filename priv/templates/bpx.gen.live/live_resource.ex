defmodule <%= inspect live_resource.module %> do
  use Backpex.LiveResource,
    layout: <%= inspect live_resource.layout %>,
    schema: <%= live_resource.schema %>,
    repo: <%= inspect live_resource.repo %>,
    update_changeset: &<%= inspect live_resource.schema %>.changeset/3,
    create_changeset: &<%= inspect live_resource.schema %>.changeset/3,
    pubsub: <%= inspect live_resource.pubsub %>,
    topic: <%= inspect live_resource.topic %>,
    event_prefix: <%= inspect live_resource.event_prefix %>

  @impl Backpex.LiveResource
  def singular_name, do: <%= inspect live_resource.singular_name %>

  @impl Backpex.LiveResource
  def plural_name, do: <%= inspect live_resource.plural_name %>

  @impl Backpex.LiveResource
  def fields do
    <%= live_resource.fields %>
  end
end
