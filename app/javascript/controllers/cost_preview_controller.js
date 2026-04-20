import { Controller } from "@hotwired/stimulus"

// Reactive credit cost preview for the new-episode form (agent-team-gq88).
//
// Hits POST /api/internal/episodes/cost_preview with the current source-type
// inputs and updates the preview element with human-readable copy:
//
//   credit user, sufficient  → "This will cost N credit(s). You have M remaining."
//   credit user, insufficient → "Not enough credits. Costs N, you have M. Buy more."
//   free tier                 → "Included — doesn't use credits."
//
// Debounces text-input events at 250ms to avoid chatty requests while typing.
// Errors are swallowed (preview reverts to em-dash) so a failed preview never
// blocks submit.
//
// Listens for `tab-switch:changed` (dispatched by tab_switch_controller) so
// switching from Paste→URL→Upload resets the preview and re-triggers it for
// the newly-active tab's current input. Without this, the preview shows
// stale copy from the previous tab (e.g. "2 credits" from a long paste
// while the user is now looking at the URL tab where cost is always 1).
export default class extends Controller {
  static targets = ["preview", "pasteText", "urlField", "uploadField"]
  static values = {
    endpoint: String
  }

  connect() {
    this._debounceTimer = null
    this._abortController = null
  }

  disconnect() {
    if (this._debounceTimer) clearTimeout(this._debounceTimer)
    if (this._abortController) this._abortController.abort()
  }

  pasteChanged() {
    const text = this.hasPasteTextTarget ? this.pasteTextTarget.value : ""
    this._debouncedRequest({ source_type: "paste", text })
  }

  urlChanged() {
    const url = this.hasUrlFieldTarget ? this.urlFieldTarget.value : ""
    this._debouncedRequest({ source_type: "url", url })
  }

  uploadChanged() {
    if (!this.hasUploadFieldTarget) return
    const file = this.uploadFieldTarget.files && this.uploadFieldTarget.files[0]
    if (!file) return
    // File change is discrete — no debounce needed.
    this._request({ source_type: "upload", upload_length: file.size })
  }

  // Triggered by tab-switch:changed (dispatched from tab_switch_controller).
  // Reset preview to the em-dash placeholder, then re-request for the
  // newly-active tab's current input so we never display a cost derived
  // from a different source type than the one the user is looking at.
  tabChanged(event) {
    // Cancel any in-flight or debounced request from the previous tab so
    // its late response can't overwrite the preview we're about to set.
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
      this._debounceTimer = null
    }
    if (this._abortController) {
      this._abortController.abort()
      this._abortController = null
    }

    this._setPreview("—")

    const selectedTab = event && event.detail && event.detail.selectedTab
    switch (selectedTab) {
      case "paste": {
        const text = this.hasPasteTextTarget ? this.pasteTextTarget.value : ""
        if (text.length > 0) this._request({ source_type: "paste", text })
        break
      }
      case "url": {
        const url = this.hasUrlFieldTarget ? this.urlFieldTarget.value : ""
        if (url.length > 0) this._request({ source_type: "url", url })
        break
      }
      case "file": {
        if (!this.hasUploadFieldTarget) break
        const file = this.uploadFieldTarget.files && this.uploadFieldTarget.files[0]
        if (file) this._request({ source_type: "upload", upload_length: file.size })
        break
      }
    }
  }

  _debouncedRequest(payload) {
    if (this._debounceTimer) clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => this._request(payload), 250)
  }

  async _request(payload) {
    if (!this.endpointValue) return

    if (this._abortController) this._abortController.abort()
    this._abortController = new AbortController()

    try {
      const response = await fetch(this.endpointValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this._csrfToken()
        },
        body: JSON.stringify(payload),
        signal: this._abortController.signal
      })

      if (!response.ok) {
        this._setPreview("—")
        return
      }

      const body = await response.json()
      this._renderPayload(body, payload.source_type)
    } catch (err) {
      if (err.name === "AbortError") return
      this._setPreview("—")
    }
  }

  _renderPayload(body, sourceType) {
    if (body.free_tier) {
      this._setPreview("Included — doesn't use credits.")
      return
    }

    const cost = body.cost
    const balance = body.balance
    const sufficient = body.sufficient
    const creditWord = cost === 1 ? "credit" : "credits"

    if (sufficient) {
      // URL previews always return cost=1 because real length isn't known
      // until the article is fetched. A long Premium-voice article can
      // end up costing 2 — surface that caveat so the preview doesn't
      // lie to the user.
      if (sourceType === "url") {
        this._setPreview(`~${cost} ${creditWord} (final cost depends on article length — long Premium-voice articles may cost 2). You have ${balance} remaining.`)
      } else {
        this._setPreview(`This will cost ${cost} ${creditWord}. You have ${balance} remaining.`)
      }
    } else {
      const node = document.createElement("span")
      node.append(`Not enough credits. This costs ${cost}, you have ${balance}. `)
      const link = document.createElement("a")
      link.href = "/billing"
      // Open in a new tab so the user doesn't lose whatever text / URL
      // they've already typed into the form when they click through.
      link.target = "_blank"
      link.rel = "noopener"
      link.className = "underline font-medium"
      link.textContent = "Buy more"
      node.appendChild(link)
      this._replacePreview(node)
    }
  }

  _setPreview(text) {
    if (!this.hasPreviewTarget) return
    this.previewTarget.textContent = text
  }

  _replacePreview(node) {
    if (!this.hasPreviewTarget) return
    this.previewTarget.replaceChildren(node)
  }

  _csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") : ""
  }
}
