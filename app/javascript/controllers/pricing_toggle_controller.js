import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["monthlyPrice", "annualPrice", "premiumLink", "priceField", "popularBadge"]
  static values = {
    monthlyPriceId: String,
    annualPriceId: String
  }

  connect() {
    this.update()
  }

  update() {
    const selected = this.element.querySelector('input[name="frequency"]:checked')?.value || "annual"
    const isAnnual = selected === "annual"

    // Toggle price visibility
    if (this.hasMonthlyPriceTarget) {
      this.monthlyPriceTarget.classList.toggle("hidden", isAnnual)
    }
    if (this.hasAnnualPriceTarget) {
      this.annualPriceTarget.classList.toggle("hidden", !isAnnual)
    }

    // Update premium button's data attributes (for signup modal)
    if (this.hasPremiumLinkTarget) {
      this.premiumLinkTarget.dataset.plan = isAnnual ? "premium_annual" : "premium_monthly"
    }

    // Update hidden form field (for direct checkout)
    if (this.hasPriceFieldTarget) {
      this.priceFieldTarget.value = isAnnual ? this.annualPriceIdValue : this.monthlyPriceIdValue
    }

    // Toggle "Most popular" badge (show for annual)
    if (this.hasPopularBadgeTarget) {
      this.popularBadgeTarget.classList.toggle("hidden", !isAnnual)
    }
  }
}
