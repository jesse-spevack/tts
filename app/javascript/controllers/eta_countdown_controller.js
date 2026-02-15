import { Controller } from "@hotwired/stimulus"

// Counts down the estimated remaining processing time for an episode.
// Receives estimated total seconds and processing start time from the server.
// Displays "~Xs remaining", then "Almost done..." when the estimate expires.
export default class extends Controller {
  static values = {
    estimatedSeconds: Number,
    startedAt: String
  }

  static targets = ["display"]

  connect() {
    this.update()
    this.timer = setInterval(() => this.update(), 1000)
  }

  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
    }
  }

  update() {
    const remaining = this.remainingSeconds()

    if (remaining > 0) {
      this.displayTarget.textContent = `~${this.formatTime(remaining)} remaining`
    } else {
      this.displayTarget.textContent = "Almost done..."
    }
  }

  remainingSeconds() {
    const startedAt = new Date(this.startedAtValue).getTime()
    const elapsed = (Date.now() - startedAt) / 1000
    return Math.ceil(this.estimatedSecondsValue - elapsed)
  }

  formatTime(seconds) {
    if (seconds >= 60) {
      const mins = Math.ceil(seconds / 60)
      return `${mins} min`
    }
    return `${seconds}s`
  }
}
