import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["monthlyPrice", "annualPrice", "premiumLink"]

  connect() {
    this.update()
  }

  update() {
    const selected = this.element.querySelector('input[name="frequency"]:checked')?.value || "monthly"
    const isAnnual = selected === "annual"

    // Toggle price visibility
    this.monthlyPriceTarget.classList.toggle("hidden", isAnnual)
    this.annualPriceTarget.classList.toggle("hidden", !isAnnual)

    // Update premium button's plan
    const plan = isAnnual ? "premium_annual" : "premium_monthly"
    this.premiumLinkTarget.dataset.plan = plan
  }
}
