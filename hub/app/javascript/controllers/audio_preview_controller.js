import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["button"]

  connect() {
    this.audio = new Audio(this.urlValue)
    this.audio.addEventListener("ended", () => this.updateButton("play"))
    this.audio.addEventListener("pause", () => this.updateButton("play"))
    this.audio.addEventListener("play", () => this.updateButton("pause"))
  }

  disconnect() {
    if (this.audio) {
      this.audio.pause()
      this.audio = null
    }
  }

  toggle(event) {
    event.preventDefault()

    if (this.audio.paused) {
      // Stop any other playing previews
      this.application.controllers
        .filter(c => c.identifier === "audio-preview" && c !== this)
        .forEach(c => c.audio?.pause())
      this.audio.play()
    } else {
      this.audio.pause()
    }
  }

  restart(event) {
    event.preventDefault()
    this.audio.currentTime = 0
    this.audio.play()
  }

  updateButton(state) {
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = state === "play" ? "▶ Preview" : "⏸ Pause"
    }
  }
}
