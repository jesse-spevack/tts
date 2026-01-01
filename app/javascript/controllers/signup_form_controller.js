import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["planField"]

  connect() {
    this.capturePlanFromUrl()
  }

  capturePlanFromUrl() {
    const hash = window.location.hash
    const match = hash.match(/[?&]plan=([^&]+)/)
    if (match && this.hasPlanFieldTarget) {
      this.planFieldTarget.value = match[1]
    }
  }
}
