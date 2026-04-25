import { Controller } from "@hotwired/stimulus"

// Highlights the nav link whose `data-step` matches the section currently in
// view. Used by the Splitting Long Articles help page.
//
// Usage:
//   <section data-controller="scroll-spy"
//            data-scroll-spy-active-class="font-medium text-mist-950"
//            data-scroll-spy-inactive-class="text-mist-500">
//     <a data-scroll-spy-target="link" data-step="1">…</a>
//     <article data-scroll-spy-target="step" data-step="1">…</article>
//   </section>
export default class extends Controller {
  static targets = ["step", "link"]
  static classes = ["active", "inactive"]

  connect() {
    if (this.stepTargets.length === 0 || typeof IntersectionObserver === "undefined") return

    this.observer = new IntersectionObserver(
      entries => this.#onIntersect(entries),
      { rootMargin: "-30% 0px -60% 0px", threshold: 0 }
    )

    this.stepTargets.forEach(step => this.observer.observe(step))
  }

  disconnect() {
    this.observer?.disconnect()
  }

  #onIntersect(entries) {
    const visible = entries.find(e => e.isIntersecting)
    if (!visible) return
    this.#activate(visible.target.dataset.step)
  }

  #activate(step) {
    this.linkTargets.forEach(link => {
      const isActive = link.dataset.step === step
      this.#applyClasses(link, isActive)
    })
  }

  #applyClasses(link, isActive) {
    const add = isActive ? this.activeClasses : this.inactiveClasses
    const remove = isActive ? this.inactiveClasses : this.activeClasses
    link.classList.add(...add)
    link.classList.remove(...remove)
  }
}
