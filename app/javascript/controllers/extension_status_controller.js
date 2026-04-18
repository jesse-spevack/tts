import { Controller } from "@hotwired/stimulus"

// Detects whether the PodRead browser extension is installed by listening for
// a `podread:extension-ready` CustomEvent dispatched by the extension's
// content script on page load. If no event arrives before the timeout, the
// status flips to "not-installed". Read-only: this controller never
// dispatches back to the extension.
export default class extends Controller {
  static targets = ["statusLabel"]
  static values = {
    status: { type: String, default: "detecting" },
    version: { type: String, default: "" },
    timeout: { type: Number, default: 500 }
  }

  connect() {
    // Belt-and-suspenders: the extension's content script both dispatches a
    // `podread:extension-ready` event AND writes its version to the <html>
    // dataset. If we connect after the event already fired (slow bundle /
    // CSP stall / Turbo lag), the dataset lets us detect synchronously
    // without waiting for the 500ms timeout to expire as "not installed".
    const eagerVersion = document.documentElement.dataset.podreadExtensionVersion
    if (eagerVersion) {
      this.versionValue = eagerVersion
      this.statusValue = "installed"
      return
    }

    this.onReady = this.onReady.bind(this)
    window.addEventListener("podread:extension-ready", this.onReady)

    this.timeoutId = setTimeout(() => {
      if (this.statusValue === "detecting") {
        this.statusValue = "not-installed"
      }
    }, this.timeoutValue)
  }

  disconnect() {
    window.removeEventListener("podread:extension-ready", this.onReady)
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
      this.timeoutId = null
    }
  }

  onReady(event) {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
      this.timeoutId = null
    }
    this.versionValue = event.detail?.extensionVersion || ""
    this.statusValue = "installed"
  }

  statusValueChanged() {
    this.render()
  }

  versionValueChanged() {
    this.render()
  }

  render() {
    if (!this.hasStatusLabelTarget) return

    switch (this.statusValue) {
      case "installed":
        this.statusLabelTarget.textContent = this.versionValue
          ? `Installed · v${this.versionValue}`
          : "Installed"
        break
      case "not-installed":
        this.statusLabelTarget.textContent = "Not installed"
        break
      default:
        this.statusLabelTarget.textContent = "Detecting…"
    }
  }
}
