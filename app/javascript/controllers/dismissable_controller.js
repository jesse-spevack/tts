import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  dismiss() {
    this.element.classList.add("opacity-0")
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}
