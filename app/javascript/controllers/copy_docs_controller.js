import { Controller } from "@hotwired/stimulus"

// Copies the innerText of the source target to the clipboard. Used by the
// "Copy for LLM" button on /docs/mpp so developers integrating against the
// MPP spec can one-click grab the whole page as plain text to paste into
// an AI assistant.
//
// Differs from clipboard_controller in that the content is pulled from the
// DOM at click time, not passed as a static value at render time.
export default class extends Controller {
  static targets = ["source", "label"]
  static values = { copiedLabel: { type: String, default: "Copied!" } }

  async copy() {
    const originalLabel = this.labelTarget.textContent
    try {
      await navigator.clipboard.writeText(this.sourceTarget.innerText)
      this.labelTarget.textContent = this.copiedLabelValue
    } catch (error) {
      this.labelTarget.textContent = "Copy failed"
      console.error("copy-docs: clipboard write failed", error)
    }
    setTimeout(() => {
      this.labelTarget.textContent = originalLabel
    }, 2000)
  }
}
