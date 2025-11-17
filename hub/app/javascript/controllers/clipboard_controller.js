import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["copyIcon", "checkIcon"]
  static values = { content: String }

  copy() {
    navigator.clipboard.writeText(this.contentValue).then(() => {
      this.showSuccess()
    })
  }

  showSuccess() {
    this.copyIconTarget.classList.add("hidden")
    this.checkIconTarget.classList.remove("hidden")

    setTimeout(() => {
      this.copyIconTarget.classList.remove("hidden")
      this.checkIconTarget.classList.add("hidden")
    }, 2000)
  }
}
