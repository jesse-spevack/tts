# HTML Metadata Extraction Design

## Problem

Currently, episode metadata (title, author, description) comes entirely from the LLM. This means:
- The LLM can hallucinate or misinterpret metadata
- We're not using authoritative data that's already in the HTML
- Wasted tokens asking the LLM for information we could extract directly

## Solution

Extract title and author from HTML metadata tags. Use HTML values as the primary source, falling back to LLM only when HTML metadata is missing.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Metadata sources | `<title>`, `<meta name="author">` | Keep it simple, covers most cases |
| Description | LLM only | No standard HTML tag, LLM generates good summaries |
| Where to extract | Extend `ArticleExtractor` | Already parsing HTML, avoid double-parse |
| Prompt changes | None | Same prompt, discard LLM values when HTML present |
| Merge strategy | HTML wins | `html_value \|\| llm_value` |

## Data Flow

```
URL → fetch HTML → extract text + metadata → LLM fills gaps → merge (HTML wins) → save episode
```

## Changes

### `ArticleExtractor`

Expand `Result` class to include metadata:

```ruby
class Result
  attr_reader :text, :error, :title, :author

  def self.success(text, title: nil, author: nil)
    new(text: text, error: nil, title: title, author: author)
  end
end
```

Add extraction methods:

```ruby
def extract_title(doc)
  doc.at_css('title')&.text&.strip.presence
end

def extract_author(doc)
  doc.at_css('meta[name="author"]')&.[]('content')&.strip.presence
end
```

### `ProcessUrlEpisode`

Update merge logic in `update_and_enqueue`:

```ruby
episode.update!(
  title: @extract_result.title || @llm_result.title,
  author: @extract_result.author || @llm_result.author,
  description: @llm_result.description
)
```

### `LlmProcessor`

No changes. Keeps working the same way.

## Testing

### `ArticleExtractor` tests

1. HTML has both title and author → returns metadata in result
2. HTML missing author → returns title, author is nil
3. HTML missing both → returns nil for both, text still extracted

### `ProcessUrlEpisode` tests

1. HTML metadata preferred over LLM → verify HTML values used when present, LLM fills gaps

## Estimate

~20 lines of new code across two files. No database changes. No new dependencies.
