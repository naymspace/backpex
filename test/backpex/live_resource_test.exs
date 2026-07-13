defmodule Backpex.LiveResourceTest do
  use ExUnit.Case, async: true

  alias Backpex.LiveResource

  describe "return_to_param/1" do
    test "returns a same-origin absolute path" do
      assert LiveResource.return_to_param(%{"return_to" => "/admin/posts"}) == "/admin/posts"
    end

    test "keeps a query string on the path" do
      assert LiveResource.return_to_param(%{"return_to" => "/admin/posts?page=2"}) == "/admin/posts?page=2"
    end

    test "rejects a value with a scheme" do
      assert LiveResource.return_to_param(%{"return_to" => "https://evil.com"}) == nil
    end

    test "rejects a protocol-relative value" do
      assert LiveResource.return_to_param(%{"return_to" => "//evil.com"}) == nil
    end

    test "rejects a backslash-prefixed value" do
      # A literal backslash (single-level escaping here); browsers may normalize it to "//".
      assert LiveResource.return_to_param(%{"return_to" => "/\\evil.com"}) == nil
    end

    test "rejects a value containing control characters" do
      assert LiveResource.return_to_param(%{"return_to" => "/foo\evil.com"}) == nil
      assert LiveResource.return_to_param(%{"return_to" => "/foo\nbar"}) == nil
    end

    test "returns nil when the param is missing" do
      assert LiveResource.return_to_param(%{}) == nil
    end

    test "returns nil when the param is not a string" do
      assert LiveResource.return_to_param(%{"return_to" => ["/admin"]}) == nil
    end
  end
end
