# frozen_string_literal: true

require "test_helper"

class UrlValidatorTest < ActiveSupport::TestCase
  test "returns true for valid http URL" do
    assert UrlValidator.valid?("http://example.com")
  end

  test "returns true for valid https URL" do
    assert UrlValidator.valid?("https://example.com/path")
  end

  test "returns false for nil" do
    assert_not UrlValidator.valid?(nil)
  end

  test "returns false for empty string" do
    assert_not UrlValidator.valid?("")
  end

  test "returns false for non-URL string" do
    assert_not UrlValidator.valid?("not a url")
  end

  test "returns false for ftp URL" do
    assert_not UrlValidator.valid?("ftp://example.com")
  end

  test "returns false for file URL" do
    assert_not UrlValidator.valid?("file:///etc/passwd")
  end

  test "returns false for javascript URL" do
    assert_not UrlValidator.valid?("javascript:alert(1)")
  end
end
