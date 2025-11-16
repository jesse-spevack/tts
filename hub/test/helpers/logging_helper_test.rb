require "test_helper"

class LoggingHelperTest < ActiveSupport::TestCase
  test "masks email with long local part" do
    assert_equal "je***@example.com", LoggingHelper.mask_email("jesse@example.com")
  end

  test "masks email with short local part" do
    assert_equal "ab***@example.com", LoggingHelper.mask_email("abc@example.com")
  end

  test "masks email with very short local part" do
    assert_equal "***@example.com", LoggingHelper.mask_email("ab@example.com")
  end

  test "masks email with single character local part" do
    assert_equal "***@example.com", LoggingHelper.mask_email("a@example.com")
  end

  test "preserves full domain" do
    assert_equal "us***@subdomain.example.co.uk", LoggingHelper.mask_email("user@subdomain.example.co.uk")
  end
end
