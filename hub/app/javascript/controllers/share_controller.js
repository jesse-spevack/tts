import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["linkIcon", "checkIcon"]
  static values = { url: String, text: String }

  copyLink() {
    navigator.clipboard.writeText(this.urlValue).then(() => {
      this.showSuccess()
    })
  }

  showSuccess() {
    this.linkIconTarget.classList.add("hidden")
    this.checkIconTarget.classList.remove("hidden")

    setTimeout(() => {
      this.linkIconTarget.classList.remove("hidden")
      this.checkIconTarget.classList.add("hidden")
    }, 2000)
  }

  // Native share API for mobile devices
  nativeShare() {
    if (navigator.share) {
      navigator.share({
        title: this.textValue,
        url: this.urlValue
      }).catch(() => {
        // User cancelled or share failed, silently ignore
      })
    } else {
      this.copyLink()
    }
  }
}
