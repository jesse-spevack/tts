import { Controller } from "@hotwired/stimulus"

const PLAN_CONTENT = {
  free: {
    heading: "Start listening free",
    subtext: "2 episodes/month, no credit card required"
  },
  premium_monthly: {
    heading: "Go Premium",
    subtext: "$9/month · Unlimited episodes · Cancel anytime"
  },
  premium_annual: {
    heading: "Go Premium",
    subtext: "$89/year · Unlimited episodes · Save 18%"
  }
}

export default class extends Controller {
  static targets = ["dialog", "heading", "subtext", "planField"]

  open(event) {
    event.preventDefault()
    const plan = event.currentTarget.dataset.plan || "free"
    this.updateContent(plan)
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  closeOnBackdrop(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  updateContent(plan) {
    const content = PLAN_CONTENT[plan] || PLAN_CONTENT.free
    this.headingTarget.textContent = content.heading
    this.subtextTarget.textContent = content.subtext
    this.planFieldTarget.value = plan === "free" ? "" : plan
  }
}
