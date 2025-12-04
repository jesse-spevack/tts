import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["button", "playIcon", "pauseIcon"]

  connect() {
    this.audio = new Audio(this.urlValue)
    this.audio.addEventListener("ended", () => this.showPlayIcon())
    this.audio.addEventListener("pause", () => this.showPlayIcon())
    this.audio.addEventListener("play", () => this.showPauseIcon())
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

  stopPropagation(event) {
    event.stopPropagation()
  }

  showPlayIcon() {
    if (this.hasPlayIconTarget && this.hasPauseIconTarget) {
      this.playIconTarget.classList.remove("hidden")
      this.pauseIconTarget.classList.add("hidden")
    }
  }

  showPauseIcon() {
    if (this.hasPlayIconTarget && this.hasPauseIconTarget) {
      this.playIconTarget.classList.add("hidden")
      this.pauseIconTarget.classList.remove("hidden")
    }
  }
}
