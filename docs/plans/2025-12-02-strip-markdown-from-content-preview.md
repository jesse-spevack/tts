# Strip Markdown from Content Preview Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Strip markdown syntax from episode content previews so users see plain text instead of raw markdown.

**Architecture:** Add a `MarkdownStripper` module to Hub that removes markdown syntax using regex patterns (copied from existing `lib/text_converter.rb`). Call this stripper in `ContentPreview.generate` before truncation.

**Tech Stack:** Ruby, Rails, regex-based markdown stripping

---

## Task 1: Add MarkdownStripper Module

**Files:**
- Create: `hub/app/services/markdown_stripper.rb`
- Test: `hub/test/services/markdown_stripper_test.rb`

### Step 1: Write the failing test for header stripping

```ruby
# hub/test/services/markdown_stripper_test.rb
# frozen_string_literal: true

require "test_helper"

class MarkdownStripperTest < ActiveSupport::TestCase
  test "removes h1 headers" do
    assert_equal "Title", MarkdownStripper.strip("# Title")
  end

  test "removes h2-h6 headers" do
    assert_equal "Subtitle", MarkdownStripper.strip("## Subtitle")
    assert_equal "Deep", MarkdownStripper.strip("###### Deep")
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: FAIL with "uninitialized constant MarkdownStripper"

### Step 3: Write minimal implementation for headers

```ruby
# hub/app/services/markdown_stripper.rb
# frozen_string_literal: true

module MarkdownStripper
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_headers(text)
    text.strip
  end

  def self.remove_headers(text)
    text.gsub(/^\#{1,6}\s+/, "")
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: PASS

### Step 5: Commit

```bash
git add hub/app/services/markdown_stripper.rb hub/test/services/markdown_stripper_test.rb
git commit -m "feat: add MarkdownStripper with header removal"
```

---

## Task 2: Add Bold/Italic Stripping

**Files:**
- Modify: `hub/app/services/markdown_stripper.rb`
- Modify: `hub/test/services/markdown_stripper_test.rb`

### Step 1: Write the failing tests

Add to `hub/test/services/markdown_stripper_test.rb`:

```ruby
  test "removes bold formatting with asterisks" do
    assert_equal "bold text", MarkdownStripper.strip("**bold text**")
  end

  test "removes bold formatting with underscores" do
    assert_equal "bold text", MarkdownStripper.strip("__bold text__")
  end

  test "removes italic formatting with asterisks" do
    assert_equal "italic text", MarkdownStripper.strip("*italic text*")
  end

  test "removes italic formatting with underscores" do
    assert_equal "italic text", MarkdownStripper.strip("_italic text_")
  end

  test "removes strikethrough" do
    assert_equal "deleted", MarkdownStripper.strip("~~deleted~~")
  end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: FAIL - bold/italic text still has asterisks/underscores

### Step 3: Add formatting removal to implementation

Add to `hub/app/services/markdown_stripper.rb`:

```ruby
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text.strip
  end

  def self.remove_formatting(text)
    text = text.gsub(/(\*\*|__)(.*?)\1/, '\2')
    text.gsub(/(\*|_)(.*?)\1/, '\2')
  end

  def self.remove_strikethrough(text)
    text.gsub(/~~(.*?)~~/, '\1')
  end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: PASS

### Step 5: Commit

```bash
git add hub/app/services/markdown_stripper.rb hub/test/services/markdown_stripper_test.rb
git commit -m "feat: add bold/italic/strikethrough stripping"
```

---

## Task 3: Add Link and Image Stripping

**Files:**
- Modify: `hub/app/services/markdown_stripper.rb`
- Modify: `hub/test/services/markdown_stripper_test.rb`

### Step 1: Write the failing tests

Add to `hub/test/services/markdown_stripper_test.rb`:

```ruby
  test "converts links to just the text" do
    assert_equal "click here", MarkdownStripper.strip("[click here](https://example.com)")
  end

  test "removes images completely" do
    assert_equal "", MarkdownStripper.strip("![alt text](image.png)").strip
  end

  test "removes images but keeps surrounding text" do
    assert_equal "Before  After", MarkdownStripper.strip("Before ![img](url) After")
  end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: FAIL - links and images still have markdown syntax

### Step 3: Add link/image removal to implementation

Add to `hub/app/services/markdown_stripper.rb`:

```ruby
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_images(text)
    text = convert_links(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text.strip
  end

  def self.remove_images(text)
    text.gsub(/!\[([^\]]*)\]\([^)]+\)/, "")
  end

  def self.convert_links(text)
    text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: PASS

### Step 5: Commit

```bash
git add hub/app/services/markdown_stripper.rb hub/test/services/markdown_stripper_test.rb
git commit -m "feat: add link and image stripping"
```

---

## Task 4: Add Code Block and Inline Code Stripping

**Files:**
- Modify: `hub/app/services/markdown_stripper.rb`
- Modify: `hub/test/services/markdown_stripper_test.rb`

### Step 1: Write the failing tests

Add to `hub/test/services/markdown_stripper_test.rb`:

```ruby
  test "removes fenced code blocks" do
    input = "Before\n```ruby\ncode here\n```\nAfter"
    assert_equal "Before\n\nAfter", MarkdownStripper.strip(input)
  end

  test "removes inline code but keeps content" do
    assert_equal "use the function method", MarkdownStripper.strip("use the `function` method")
  end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: FAIL - code blocks still present

### Step 3: Add code removal to implementation

Add to `hub/app/services/markdown_stripper.rb`:

```ruby
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_code_blocks(text)
    text = remove_images(text)
    text = convert_links(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text = remove_inline_code(text)
    text.strip
  end

  def self.remove_code_blocks(text)
    text.gsub(/```[\s\S]*?```/m, "")
  end

  def self.remove_inline_code(text)
    text.gsub(/`([^`]+)`/, '\1')
  end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: PASS

### Step 5: Commit

```bash
git add hub/app/services/markdown_stripper.rb hub/test/services/markdown_stripper_test.rb
git commit -m "feat: add code block and inline code stripping"
```

---

## Task 5: Add List and Blockquote Stripping

**Files:**
- Modify: `hub/app/services/markdown_stripper.rb`
- Modify: `hub/test/services/markdown_stripper_test.rb`

### Step 1: Write the failing tests

Add to `hub/test/services/markdown_stripper_test.rb`:

```ruby
  test "removes unordered list markers" do
    assert_equal "item one\nitem two", MarkdownStripper.strip("- item one\n- item two")
  end

  test "removes ordered list markers" do
    assert_equal "first\nsecond", MarkdownStripper.strip("1. first\n2. second")
  end

  test "removes blockquote markers" do
    assert_equal "quoted text", MarkdownStripper.strip("> quoted text")
  end

  test "removes horizontal rules" do
    assert_equal "Above\n\nBelow", MarkdownStripper.strip("Above\n---\nBelow")
  end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: FAIL - list markers and blockquotes still present

### Step 3: Add list/blockquote removal to implementation

Add to `hub/app/services/markdown_stripper.rb`:

```ruby
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_code_blocks(text)
    text = remove_images(text)
    text = convert_links(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text = remove_inline_code(text)
    text = remove_unordered_lists(text)
    text = remove_ordered_lists(text)
    text = remove_blockquotes(text)
    text = remove_horizontal_rules(text)
    text.strip
  end

  def self.remove_unordered_lists(text)
    text.gsub(/^\s*[-*+]\s+/, "")
  end

  def self.remove_ordered_lists(text)
    text.gsub(/^\s*\d+\.\s+/, "")
  end

  def self.remove_blockquotes(text)
    text.gsub(/^\s*>\s?/, "")
  end

  def self.remove_horizontal_rules(text)
    text.gsub(/^(\*{3,}|-{3,}|_{3,})$/, "")
  end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: PASS

### Step 5: Commit

```bash
git add hub/app/services/markdown_stripper.rb hub/test/services/markdown_stripper_test.rb
git commit -m "feat: add list and blockquote stripping"
```

---

## Task 6: Add HTML and YAML Frontmatter Stripping

**Files:**
- Modify: `hub/app/services/markdown_stripper.rb`
- Modify: `hub/test/services/markdown_stripper_test.rb`

### Step 1: Write the failing tests

Add to `hub/test/services/markdown_stripper_test.rb`:

```ruby
  test "removes HTML tags" do
    assert_equal "plain text", MarkdownStripper.strip("<div>plain text</div>")
  end

  test "removes YAML frontmatter" do
    input = "---\ntitle: Test\nauthor: Me\n---\nContent here"
    assert_equal "Content here", MarkdownStripper.strip(input)
  end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: FAIL - HTML tags and YAML frontmatter still present

### Step 3: Add HTML/YAML removal to implementation

Add to `hub/app/services/markdown_stripper.rb`:

```ruby
  def self.strip(text)
    return text if text.nil?

    text = text.dup
    text = remove_yaml_frontmatter(text)
    text = remove_code_blocks(text)
    text = remove_images(text)
    text = convert_links(text)
    text = remove_html_tags(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text = remove_inline_code(text)
    text = remove_unordered_lists(text)
    text = remove_ordered_lists(text)
    text = remove_blockquotes(text)
    text = remove_horizontal_rules(text)
    text.strip
  end

  def self.remove_yaml_frontmatter(text)
    text.gsub(/\A---\s*\n.*?\n---\s*\n/m, "")
  end

  def self.remove_html_tags(text)
    text.gsub(/<[^>]+>/, "")
  end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: PASS

### Step 5: Commit

```bash
git add hub/app/services/markdown_stripper.rb hub/test/services/markdown_stripper_test.rb
git commit -m "feat: add HTML and YAML frontmatter stripping"
```

---

## Task 7: Add Whitespace Cleanup

**Files:**
- Modify: `hub/app/services/markdown_stripper.rb`
- Modify: `hub/test/services/markdown_stripper_test.rb`

### Step 1: Write the failing tests

Add to `hub/test/services/markdown_stripper_test.rb`:

```ruby
  test "collapses multiple newlines into double newlines" do
    input = "Para one\n\n\n\n\nPara two"
    assert_equal "Para one\n\nPara two", MarkdownStripper.strip(input)
  end

  test "handles nil input" do
    assert_nil MarkdownStripper.strip(nil)
  end

  test "handles empty string" do
    assert_equal "", MarkdownStripper.strip("")
  end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: FAIL - multiple newlines not collapsed

### Step 3: Add whitespace cleanup to implementation

Modify the `strip` method in `hub/app/services/markdown_stripper.rb`:

```ruby
  def self.strip(text)
    return text if text.nil?
    return text if text.empty?

    text = text.dup
    text = remove_yaml_frontmatter(text)
    text = remove_code_blocks(text)
    text = remove_images(text)
    text = convert_links(text)
    text = remove_html_tags(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text = remove_inline_code(text)
    text = remove_unordered_lists(text)
    text = remove_ordered_lists(text)
    text = remove_blockquotes(text)
    text = remove_horizontal_rules(text)
    text = clean_whitespace(text)
    text
  end

  def self.clean_whitespace(text)
    text.gsub(/\n{3,}/, "\n\n").strip
  end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/markdown_stripper_test.rb`
Expected: PASS

### Step 5: Commit

```bash
git add hub/app/services/markdown_stripper.rb hub/test/services/markdown_stripper_test.rb
git commit -m "feat: add whitespace cleanup and edge case handling"
```

---

## Task 8: Integrate MarkdownStripper into ContentPreview

**Files:**
- Modify: `hub/app/services/content_preview.rb`
- Modify: `hub/test/services/content_preview_test.rb`

### Step 1: Write the failing tests

Add to `hub/test/services/content_preview_test.rb`:

```ruby
  test "strips markdown headers before generating preview" do
    markdown = "# Title\n\nThis is the content"
    result = ContentPreview.generate(markdown)
    refute_includes result, "#"
    assert_includes result, "Title"
  end

  test "strips markdown formatting before generating preview" do
    markdown = "**Bold** and *italic* text"
    result = ContentPreview.generate(markdown)
    refute_includes result, "*"
    assert_includes result, "Bold"
    assert_includes result, "italic"
  end

  test "strips markdown links before generating preview" do
    markdown = "Click [here](https://example.com) to continue"
    result = ContentPreview.generate(markdown)
    refute_includes result, "["
    refute_includes result, "]"
    refute_includes result, "("
    assert_includes result, "here"
  end

  test "strips complex markdown document" do
    markdown = <<~MD
      # Welcome

      This is **important** content with a [link](http://example.com).

      - Item one
      - Item two

      > A quote here
    MD
    result = ContentPreview.generate(markdown)
    refute_includes result, "#"
    refute_includes result, "**"
    refute_includes result, "["
    refute_includes result, "-"
    refute_includes result, ">"
  end
```

### Step 2: Run test to verify it fails

Run: `bin/rails test test/services/content_preview_test.rb`
Expected: FAIL - markdown syntax still present in preview

### Step 3: Integrate MarkdownStripper into ContentPreview

Modify `hub/app/services/content_preview.rb`:

```ruby
# frozen_string_literal: true

class ContentPreview
  PREVIEW_LENGTH = 60
  ELLIPSIS = "..."

  def self.generate(text)
    return nil if text.nil?

    text = MarkdownStripper.strip(text)
    return text if text.empty?

    # If text is short enough, return as-is
    # Need room for: start(57) + ellipsis(3) + space + quote + space + quote + ellipsis(3) + end(57)
    min_truncation_length = (PREVIEW_LENGTH * 2) + 10
    return text if text.length <= min_truncation_length

    start_chars = PREVIEW_LENGTH - ELLIPSIS.length
    end_chars = PREVIEW_LENGTH - ELLIPSIS.length

    start_part = text[0, start_chars].strip
    end_part = text[-end_chars, end_chars].strip

    "#{start_part}... #{end_part}"
  end
end
```

### Step 4: Run test to verify it passes

Run: `bin/rails test test/services/content_preview_test.rb`
Expected: PASS

### Step 5: Run full test suite for Hub

Run: `bin/rails test`
Expected: All tests pass

### Step 6: Commit

```bash
git add hub/app/services/content_preview.rb hub/test/services/content_preview_test.rb
git commit -m "feat: integrate MarkdownStripper into ContentPreview"
```

---

## Task 9: Final Verification

### Step 1: Run all Hub tests

Run: `bin/rails test`
Expected: All tests pass

### Step 2: Manual verification (optional)

Start Rails console and test with real markdown:

```ruby
markdown = "# Hello World\n\nThis is **bold** and [a link](http://example.com)."
ContentPreview.generate(markdown)
# Expected: "Hello World  This is bold and a link."
```

### Step 3: Commit if any cleanup needed

If any fixes were needed, commit them:

```bash
git add -A
git commit -m "fix: address test feedback"
```

---

## Complete File References

### Final `hub/app/services/markdown_stripper.rb`

```ruby
# frozen_string_literal: true

module MarkdownStripper
  def self.strip(text)
    return text if text.nil?
    return text if text.empty?

    text = text.dup
    text = remove_yaml_frontmatter(text)
    text = remove_code_blocks(text)
    text = remove_images(text)
    text = convert_links(text)
    text = remove_html_tags(text)
    text = remove_headers(text)
    text = remove_formatting(text)
    text = remove_strikethrough(text)
    text = remove_inline_code(text)
    text = remove_unordered_lists(text)
    text = remove_ordered_lists(text)
    text = remove_blockquotes(text)
    text = remove_horizontal_rules(text)
    text = clean_whitespace(text)
    text
  end

  def self.remove_yaml_frontmatter(text)
    text.gsub(/\A---\s*\n.*?\n---\s*\n/m, "")
  end

  def self.remove_code_blocks(text)
    text.gsub(/```[\s\S]*?```/m, "")
  end

  def self.remove_images(text)
    text.gsub(/!\[([^\]]*)\]\([^)]+\)/, "")
  end

  def self.convert_links(text)
    text.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
  end

  def self.remove_html_tags(text)
    text.gsub(/<[^>]+>/, "")
  end

  def self.remove_headers(text)
    text.gsub(/^\#{1,6}\s+/, "")
  end

  def self.remove_formatting(text)
    text = text.gsub(/(\*\*|__)(.*?)\1/, '\2')
    text.gsub(/(\*|_)(.*?)\1/, '\2')
  end

  def self.remove_strikethrough(text)
    text.gsub(/~~(.*?)~~/, '\1')
  end

  def self.remove_inline_code(text)
    text.gsub(/`([^`]+)`/, '\1')
  end

  def self.remove_unordered_lists(text)
    text.gsub(/^\s*[-*+]\s+/, "")
  end

  def self.remove_ordered_lists(text)
    text.gsub(/^\s*\d+\.\s+/, "")
  end

  def self.remove_blockquotes(text)
    text.gsub(/^\s*>\s?/, "")
  end

  def self.remove_horizontal_rules(text)
    text.gsub(/^(\*{3,}|-{3,}|_{3,})$/, "")
  end

  def self.clean_whitespace(text)
    text.gsub(/\n{3,}/, "\n\n").strip
  end
end
```

### Final `hub/test/services/markdown_stripper_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class MarkdownStripperTest < ActiveSupport::TestCase
  test "removes h1 headers" do
    assert_equal "Title", MarkdownStripper.strip("# Title")
  end

  test "removes h2-h6 headers" do
    assert_equal "Subtitle", MarkdownStripper.strip("## Subtitle")
    assert_equal "Deep", MarkdownStripper.strip("###### Deep")
  end

  test "removes bold formatting with asterisks" do
    assert_equal "bold text", MarkdownStripper.strip("**bold text**")
  end

  test "removes bold formatting with underscores" do
    assert_equal "bold text", MarkdownStripper.strip("__bold text__")
  end

  test "removes italic formatting with asterisks" do
    assert_equal "italic text", MarkdownStripper.strip("*italic text*")
  end

  test "removes italic formatting with underscores" do
    assert_equal "italic text", MarkdownStripper.strip("_italic text_")
  end

  test "removes strikethrough" do
    assert_equal "deleted", MarkdownStripper.strip("~~deleted~~")
  end

  test "converts links to just the text" do
    assert_equal "click here", MarkdownStripper.strip("[click here](https://example.com)")
  end

  test "removes images completely" do
    assert_equal "", MarkdownStripper.strip("![alt text](image.png)").strip
  end

  test "removes images but keeps surrounding text" do
    assert_equal "Before  After", MarkdownStripper.strip("Before ![img](url) After")
  end

  test "removes fenced code blocks" do
    input = "Before\n```ruby\ncode here\n```\nAfter"
    assert_equal "Before\n\nAfter", MarkdownStripper.strip(input)
  end

  test "removes inline code but keeps content" do
    assert_equal "use the function method", MarkdownStripper.strip("use the `function` method")
  end

  test "removes unordered list markers" do
    assert_equal "item one\nitem two", MarkdownStripper.strip("- item one\n- item two")
  end

  test "removes ordered list markers" do
    assert_equal "first\nsecond", MarkdownStripper.strip("1. first\n2. second")
  end

  test "removes blockquote markers" do
    assert_equal "quoted text", MarkdownStripper.strip("> quoted text")
  end

  test "removes horizontal rules" do
    assert_equal "Above\n\nBelow", MarkdownStripper.strip("Above\n---\nBelow")
  end

  test "removes HTML tags" do
    assert_equal "plain text", MarkdownStripper.strip("<div>plain text</div>")
  end

  test "removes YAML frontmatter" do
    input = "---\ntitle: Test\nauthor: Me\n---\nContent here"
    assert_equal "Content here", MarkdownStripper.strip(input)
  end

  test "collapses multiple newlines into double newlines" do
    input = "Para one\n\n\n\n\nPara two"
    assert_equal "Para one\n\nPara two", MarkdownStripper.strip(input)
  end

  test "handles nil input" do
    assert_nil MarkdownStripper.strip(nil)
  end

  test "handles empty string" do
    assert_equal "", MarkdownStripper.strip("")
  end
end
```
