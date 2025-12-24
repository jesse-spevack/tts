import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]
  static values = {
    currentFrame: { type: Number, default: 0 },
    paused: { type: Boolean, default: false }
  }

  // Frame durations in milliseconds
  frameDurations = [2000, 500, 2500, 2000, 1000, 3500]

  connect() {
    if (this.prefersReducedMotion) {
      this.showStaticFallback()
      return
    }
    this.startAnimation()
  }

  disconnect() {
    this.stopAnimation()
  }

  startAnimation() {
    this.showFrame(0)
    this.scheduleNextFrame()
  }

  stopAnimation() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
  }

  scheduleNextFrame() {
    const duration = this.frameDurations[this.currentFrameValue]
    this.timeout = setTimeout(() => {
      this.advanceFrame()
    }, duration)
  }

  advanceFrame() {
    const nextFrame = (this.currentFrameValue + 1) % this.frameTargets.length
    this.showFrame(nextFrame)
    this.scheduleNextFrame()
  }

  showFrame(index) {
    this.currentFrameValue = index
    this.frameTargets.forEach((frame, i) => {
      if (i === index) {
        frame.classList.remove("hidden", "opacity-0")
        frame.classList.add("opacity-100")
      } else {
        frame.classList.add("hidden", "opacity-0")
        frame.classList.remove("opacity-100")
      }
    })
  }

  showStaticFallback() {
    // Show only the final "success" frame for reduced motion
    this.frameTargets.forEach((frame, i) => {
      if (i === 3) { // Episode created frame
        frame.classList.remove("hidden", "opacity-0")
      } else {
        frame.classList.add("hidden")
      }
    })
  }

  get prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
