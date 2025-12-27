import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "hamburgerIcon", "closeIcon"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
    this.hamburgerIconTarget.classList.toggle("hidden")
    this.closeIconTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.hamburgerIconTarget.classList.remove("hidden")
    this.closeIconTarget.classList.add("hidden")
  }
}
