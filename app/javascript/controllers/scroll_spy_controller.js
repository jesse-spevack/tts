import { Controller } from "@hotwired/stimulus"

// Sets `aria-current="step"` on the nav link whose `data-step` matches the
// section currently in view, and removes it from the others. Style the active
// state in markup with the `aria-[current=step]:…` Tailwind variant.
//
// Usage:
//   <section data-controller="scroll-spy">
//     <a data-scroll-spy-target="link" data-step="1"
//        class="… aria-[current=step]:bg-mist-950 …">…</a>
//     <article data-scroll-spy-target="step" data-step="1">…</article>
//   </section>
export default class extends Controller {
  static targets = ["step", "link"]

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
      if (link.dataset.step === step) {
        link.setAttribute("aria-current", "step")
      } else {
        link.removeAttribute("aria-current")
      }
    })
  }
}
