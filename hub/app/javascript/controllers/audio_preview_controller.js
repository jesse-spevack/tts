import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  play(event) {
    event.preventDefault()

    if (this.audio) {
      this.audio.pause()
    }

    this.audio = new Audio(this.urlValue)
    this.audio.play()
  }
}
