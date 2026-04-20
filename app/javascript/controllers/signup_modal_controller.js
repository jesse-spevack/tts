import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "heading", "subtext", "planField", "packSizeField"]

  open(event) {
    event.preventDefault()
    const { plan, packSize, heading, subtext } = event.currentTarget.dataset
    this.headingTarget.textContent = heading || "Start listening free"
    this.subtextTarget.textContent = subtext || "2 episodes/month, no credit card required"
    this.planFieldTarget.value = plan === "free" ? "" : (plan || "")
    if (this.hasPackSizeFieldTarget) {
      this.packSizeFieldTarget.value = packSize || ""
    }
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
