# frozen_string_literal: true

require "test_helper"

class ValidatesUrlTest < ActiveSupport::TestCase
  test "returns true for valid http URL" do
    assert ValidatesUrl.valid?("http://example.com")
  end

  test "returns true for valid https URL" do
    assert ValidatesUrl.valid?("https://example.com/path")
  end

  test "returns false for nil" do
    assert_not ValidatesUrl.valid?(nil)
  end

  test "returns false for empty string" do
    assert_not ValidatesUrl.valid?("")
  end

  test "returns false for non-URL string" do
    assert_not ValidatesUrl.valid?("not a url")
  end

  test "returns false for ftp URL" do
    assert_not ValidatesUrl.valid?("ftp://example.com")
  end

  test "returns false for file URL" do
    assert_not ValidatesUrl.valid?("file:///etc/passwd")
  end

  test "returns false for javascript URL" do
    assert_not ValidatesUrl.valid?("javascript:alert(1)")
  end
end
