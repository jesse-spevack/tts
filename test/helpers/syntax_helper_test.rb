require "test_helper"

class SyntaxHelperTest < ActionView::TestCase
  test "highlight(:bash, ...) wraps bash flags in a token span" do
    result = highlight(:bash, "curl -X POST https://example.com")
    assert_includes result, "<span"
    assert_includes result, "-X"
    assert_match %r{<span class="nt">-X</span>}, result
    assert result.html_safe?
  end

  test "highlight(:json, ...) marks keys and string values with distinct classes" do
    result = highlight(:json, '{"status": "complete"}')
    assert_match %r{<span class="nl">"status"</span>}, result
    assert_match %r{<span class="s2">"complete"</span>}, result
    assert result.html_safe?
  end

  test "highlight HTML-escapes angle brackets from the source" do
    result = highlight(:bash, 'curl -H "Authorization: Payment <credential>"')
    refute_includes result, "<credential>"
    assert_includes result, "&lt;credential&gt;"
  end

  test "highlight falls back to plain text for unknown languages" do
    result = highlight(:cobol, "HELLO WORLD")
    assert_includes result, "HELLO WORLD"
    assert result.html_safe?
  end
end
