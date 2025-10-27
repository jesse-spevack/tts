# Generate Input Markdown

You are helping create a markdown input file for a text-to-speech podcast generator.

## Your Task

The user has pasted article text. You need to:

1. **Extract metadata** from the article:
   - Title (from the first heading or prominent title)
   - Author name (look for bylines like "By Author Name" or "Author Name • Date")
   - Generate a concise 1-2 sentence description summarizing the article's main points

2. **Clean up the content**:
   - Remove any newsletter/subscription footers (e.g., "Subscribe to...", "This is a reader-supported publication")
   - Remove inline footnote references (numbers like 1, 2, 3)
   - Remove editorial notes in parentheses if they're not part of the main narrative
   - Convert list items that are numbered with footnotes to proper markdown headings if they're section headers
   - Keep the natural flow and narrative structure
   - Preserve all substantive content

3. **Format the markdown file**:
   - Add YAML frontmatter with title, description, and author
   - Convert sections to proper markdown headings (## for main sections, ### for subsections)
   - Ensure proper spacing and readability

4. **Generate filename**:
   - Use format: `YYYY-MM-DD-title-slug.md`
   - Today's date is the current date
   - Create a URL-friendly slug from the title (lowercase, hyphens, no special characters)

5. **Write the file**:
   - Save to `input/YYYY-MM-DD-title-slug.md`
   - Show the user the filename and character count
   - Confirm the file is ready for podcast generation

## Example Output Format

```markdown
---
title: "Article Title Here"
description: "Brief 1-2 sentence summary of the article's main points."
author: "Author Name"
---

# Article Title Here

Introduction paragraph...

## Main Section

Content here...

## Another Section

More content...
```

## Important Notes

- The frontmatter is critical - it's used for podcast metadata
- Remove clutter but preserve the author's voice and all substantive content
- Use proper markdown formatting for readability
- TTS will read everything after the frontmatter, so keep it clean and conversational

After creating the file, tell the user:
- The filename created
- The character count (for estimating podcast length)
- Confirm it's ready to generate with: `ruby generate.rb input/YYYY-MM-DD-filename.md`
