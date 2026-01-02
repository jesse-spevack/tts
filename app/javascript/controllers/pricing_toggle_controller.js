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

    // Update premium button's data attributes
    if (isAnnual) {
      this.premiumLinkTarget.dataset.plan = "premium_annual"
      this.premiumLinkTarget.dataset.heading = "Go Premium"
      this.premiumLinkTarget.dataset.subtext = "$89/year · Unlimited episodes · Save 18%"
    } else {
      this.premiumLinkTarget.dataset.plan = "premium_monthly"
      this.premiumLinkTarget.dataset.heading = "Go Premium"
      this.premiumLinkTarget.dataset.subtext = "$9/month · Unlimited episodes · Cancel anytime"
    }
  }
}
