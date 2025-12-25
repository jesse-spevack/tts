import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame", "replay", "overlay", "container"]
  static values = {
    currentFrame: { type: Number, default: 0 },
    paused: { type: Boolean, default: false }
  }

  // Frame durations in milliseconds
  // 1: Input (2s typing)
  // 2: Click (0.5s)
  // 3: Processing (2.5s)
  // 4: Success (2s)
  // 5: Transition (2s)
  // 6: Podcast app (4s, then shows replay)
  frameDurations = [2000, 500, 2500, 2000, 2000, 4000]

  connect() {
    if (this.prefersReducedMotion) {
      this.showStaticFallback()
      return
    }
    // Don't auto-start - wait for user to click play
  }

  play() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
    // Hide border from container (keep padding to prevent layout shift)
    if (this.hasContainerTarget) {
      this.containerTarget.classList.remove("border-[var(--color-text)]/20")
      this.containerTarget.classList.add("border-transparent")
    }
    // Trigger typing animation
    const typingText = this.element.querySelector("[data-typing-text]")
    const typingCursor = this.element.querySelector("[data-typing-cursor]")
    if (typingText) {
      typingText.classList.add("animate-typing")
    }
    if (typingCursor) {
      typingCursor.style.display = ""
    }
    this.startAnimation()
  }

  disconnect() {
    this.stopAnimation()
  }

  startAnimation() {
    // Frame 0 is already visible in HTML, just schedule next
    this.currentFrameValue = 0
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
      if (this.currentFrameValue === this.frameTargets.length - 1) {
        this.showReplayButton()
      } else {
        this.advanceFrame()
      }
    }, duration)
  }

  advanceFrame() {
    const nextFrame = this.currentFrameValue + 1
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

  showReplayButton() {
    if (this.hasReplayTarget) {
      this.replayTarget.classList.remove("invisible", "opacity-0")
    }
  }

  replay() {
    if (this.hasReplayTarget) {
      this.replayTarget.classList.add("invisible", "opacity-0")
    }
    this.showFrame(0)
    this.scheduleNextFrame()
  }

  showStaticFallback() {
    // Hide overlay for reduced motion users
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
    // Show only the "success" frame for reduced motion (index 3)
    this.frameTargets.forEach((frame, i) => {
      if (i === 3) {
        frame.classList.remove("hidden", "opacity-0")
        frame.classList.add("opacity-100")
      } else {
        frame.classList.add("hidden")
      }
    })
  }

  get prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
