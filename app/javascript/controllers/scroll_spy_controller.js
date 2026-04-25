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
    if (this.stepTargets.length === 0) return

    this.onScroll = () => this.#updateActive()
    window.addEventListener("scroll", this.onScroll, { passive: true })
    window.addEventListener("resize", this.onScroll, { passive: true })
    this.#updateActive()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("resize", this.onScroll)
  }

  // Active step = the last one whose top has scrolled above the activation
  // line (40% from the viewport top). Steps are evaluated in DOM order, so
  // scrolling back to the top correctly reverts to step 1.
  #updateActive() {
    const activationLine = window.innerHeight * 0.4
    let active = this.stepTargets[0]
    for (const step of this.stepTargets) {
      if (step.getBoundingClientRect().top <= activationLine) {
        active = step
      } else {
        break
      }
    }
    this.#activate(active.dataset.step)
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
