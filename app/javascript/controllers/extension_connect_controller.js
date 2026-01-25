import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = { token: String }

  connect() {
    this.setBodyAttributes()
    this.dispatchTokenEvent()
    this.updateStatusAfterDelay()
  }

  setBodyAttributes() {
    document.body.setAttribute("data-tts-token", this.tokenValue)
    document.body.setAttribute("data-tts-connect-status", "ready")
  }

  dispatchTokenEvent() {
    window.dispatchEvent(new CustomEvent("tts-extension-token", {
      detail: { token: this.tokenValue }
    }))
  }

  updateStatusAfterDelay() {
    setTimeout(() => {
      this.statusTarget.textContent = "Your extension is now connected."
    }, 500)
  }
}
