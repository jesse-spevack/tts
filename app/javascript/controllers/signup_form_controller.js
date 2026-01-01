import { Controller } from "@hotwired/stimulus"

const VALID_PLANS = ["premium_monthly", "premium_annual"]

export default class extends Controller {
  static targets = ["planField"]

  connect() {
    this.capturePlanFromUrl()
  }

  capturePlanFromUrl() {
    const hash = window.location.hash
    const match = hash.match(/[?&]plan=([^&]+)/)
    if (match && this.hasPlanFieldTarget) {
      const plan = decodeURIComponent(match[1])
      if (VALID_PLANS.includes(plan)) {
        this.planFieldTarget.value = plan
      }
    }
  }
}
