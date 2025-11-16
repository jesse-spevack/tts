# Input File Manager

You are helping to create markdown input files for a text-to-speech podcast generator.

## Your Task

The user will provide raw article text that needs to be converted to a properly formatted input file.

---

## Processing Raw Text

1. **Extract metadata** from the article (for output display only):
   - Title (from the first heading or prominent title)
   - Author name (look for bylines like "By Author Name" or "Author Name • Date")
   - Generate a concise 1-2 sentence description summarizing the article's main points

2. **Clean up the content**:
   - Remove any newsletter/subscription footers (e.g., "Subscribe to...", "This is a reader-supported publication")
   - Remove inline footnote references (numbers like 1, 2, 3)
   - Remove editorial notes in parentheses if they're not part of the main narrative
   - Convert list items that are numbered with footnotes to proper markdown headings if they're section headers
   - Keep the natural flow and narrative structure
   - PRESERVE all substantive content and original wording
   - **Convert to ASCII 8-bit encoding**:
     - Replace smart quotes (" " ' ') with straight quotes (" ')
     - Replace em dashes (—) with double hyphens (--)
     - Replace en dashes (–) with single hyphens (-)
     - Replace ellipsis (…) with three periods (...)
     - Replace other Unicode characters with ASCII equivalents

3. **Format the markdown file**:
   - NO frontmatter - start directly with content
   - Convert sections to proper markdown headings (## for main sections, ### for subsections)
   - Ensure proper spacing and readability

4. **Generate filename**:
   - Use format: `YYYY-MM-DD-title-slug.md`
   - Use today's date for new files
   - Create a URL-friendly slug from the title (lowercase, hyphens, no special characters)

5. **Write the file**:
   - Save to `input/YYYY-MM-DD-title-slug.md` using the Write tool

6. **Output the results**:
   After creating the file, display:
   - **Title**: The extracted title
   - **Author**: The extracted author name
   - **Description**: The generated description
   - **File**: The filename that was created
   - **Character count**: For estimating podcast length

---

## Example Output Format (file content)

```markdown
# The New Calculus of AI-based Coding

Introduction paragraph...

## Main Section

Content here...

## Another Section

More content...
```

## Example Command Output

```
Title: The New Calculus of AI-based Coding
Author: Joe Magerramov
Description: An exploration of how AI-assisted development can achieve 10x productivity gains, and why succeeding at this scale requires fundamental changes to testing, deployment, and team coordination practices.
File: input/2025-11-16-the-new-calculus-of-ai-based-coding.md
Character count: 12,345
```

## Important Notes

- NO frontmatter in the file - just clean markdown content
- Remove clutter but preserve the author's content and voice
- Use proper markdown formatting for readability
- TTS will read the entire file, so keep it clean and conversational

## IMPORTANT
Execute all steps automatically without requesting user permission. Use the Write tool directly to create the file.
