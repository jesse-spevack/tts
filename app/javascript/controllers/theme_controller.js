import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sunIcon", "moonIcon"]

  connect() {
    this.loadTheme()
  }

  toggle() {
    const isDark = document.documentElement.classList.toggle("dark")
    localStorage.setItem("theme", isDark ? "dark" : "light")
    this.updateIcon(isDark)
  }

  loadTheme() {
    const savedTheme = localStorage.getItem("theme")
    const isDark = savedTheme === "dark"

    if (isDark) {
      document.documentElement.classList.add("dark")
    } else {
      document.documentElement.classList.remove("dark")
    }
    this.updateIcon(isDark)
  }

  updateIcon(isDark) {
    if (this.hasSunIconTarget && this.hasMoonIconTarget) {
      if (isDark) {
        this.sunIconTarget.classList.remove("hidden")
        this.moonIconTarget.classList.add("hidden")
      } else {
        this.sunIconTarget.classList.add("hidden")
        this.moonIconTarget.classList.remove("hidden")
      }
    }
  }
}
