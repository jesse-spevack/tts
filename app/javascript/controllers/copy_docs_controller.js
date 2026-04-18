import { Controller } from "@hotwired/stimulus"
import TurndownService from "turndown"

// Copies the source target as Markdown to the clipboard. Used by the
// "Copy for LLM" button on /docs/mpp so developers integrating against
// the MPP spec can one-click grab the whole page as Markdown to paste
// into an AI assistant.
//
// Client-side HTML→Markdown conversion via Turndown keeps the ERB as
// the single source of truth — no separate .md template to maintain.
// Nodes marked with data-copy-skip are removed before conversion so
// the responsive-table partial's mobile card lists (duplicates of the
// desktop tables) and the copy button itself don't leak into the output.
export default class extends Controller {
  static targets = ["source", "label"]
  static values = { copiedLabel: { type: String, default: "Copied!" } }

  async copy() {
    const originalLabel = this.labelTarget.textContent
    try {
      const markdown = this.sourceAsMarkdown()
      await navigator.clipboard.writeText(markdown)
      this.labelTarget.textContent = this.copiedLabelValue
    } catch (error) {
      this.labelTarget.textContent = "Copy failed"
      console.error("copy-docs: clipboard write failed", error)
    }
    setTimeout(() => {
      this.labelTarget.textContent = originalLabel
    }, 2000)
  }

  sourceAsMarkdown() {
    // Clone the source so we can strip skip-marked nodes without mutating
    // the live DOM.
    const clone = this.sourceTarget.cloneNode(true)
    clone.querySelectorAll("[data-copy-skip]").forEach((node) => node.remove())

    const turndown = new TurndownService({
      headingStyle: "atx",
      codeBlockStyle: "fenced",
      bulletListMarker: "-",
      emDelimiter: "*"
    })
    // Rouge-highlighted <pre><code class="highlight"><span class="...">...</span></code></pre>
    // — preserve the fenced code block but strip the inline highlight spans.
    turndown.addRule("rougeCode", {
      filter: (node) => node.nodeName === "PRE" && node.querySelector("code.highlight"),
      replacement: (_content, node) => {
        const text = node.textContent.replace(/\n+$/, "")
        return `\n\n\`\`\`\n${text}\n\`\`\`\n\n`
      }
    })

    return turndown.turndown(clone.innerHTML).trim() + "\n"
  }
}
