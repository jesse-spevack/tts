import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "heading", "subtext", "planField"]

  open(event) {
    event.preventDefault()
    const { plan, heading, subtext } = event.currentTarget.dataset
    this.headingTarget.textContent = heading || "Start listening free"
    this.subtextTarget.textContent = subtext || "2 episodes/month, no credit card required"
    this.planFieldTarget.value = plan === "free" ? "" : (plan || "")
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
}
