import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const selectedTab = event.currentTarget.dataset.tab

    // Update tab styles
    this.tabTargets.forEach(tab => {
      if (tab.dataset.tab === selectedTab) {
        tab.classList.add("bg-[var(--color-surface0)]", "text-[var(--color-text)]")
        tab.classList.remove("text-[var(--color-subtext)]")
      } else {
        tab.classList.remove("bg-[var(--color-surface0)]", "text-[var(--color-text)]")
        tab.classList.add("text-[var(--color-subtext)]")
      }
    })

    // Show/hide panels
    this.panelTargets.forEach(panel => {
      if (panel.dataset.tab === selectedTab) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
      }
    })
  }
}
