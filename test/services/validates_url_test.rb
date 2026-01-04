# frozen_string_literal: true

require "test_helper"

class ValidatesUrlTest < ActiveSupport::TestCase
  test "returns true for valid http URL" do
    assert ValidatesUrl.call("http://example.com")
  end

  test "returns true for valid https URL" do
    assert ValidatesUrl.call("https://example.com/path")
  end

  test "returns false for nil" do
    assert_not ValidatesUrl.call(nil)
  end

  test "returns false for empty string" do
    assert_not ValidatesUrl.call("")
  end

  test "returns false for non-URL string" do
    assert_not ValidatesUrl.call("not a url")
  end

  test "returns false for ftp URL" do
    assert_not ValidatesUrl.call("ftp://example.com")
  end

  test "returns false for file URL" do
    assert_not ValidatesUrl.call("file:///etc/passwd")
  end

  test "returns false for javascript URL" do
    assert_not ValidatesUrl.call("javascript:alert(1)")
  end
end
