import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const selectedTab = event.currentTarget.dataset.tab

    // Update tab styles
    this.tabTargets.forEach(tab => {
      if (tab.dataset.tab === selectedTab) {
        tab.classList.add("border-b-2", "border-mist-950", "text-mist-950", "dark:border-white", "dark:text-white")
        tab.classList.remove("text-mist-500", "dark:text-mist-400", "hover:text-mist-700", "dark:hover:text-mist-300")
      } else {
        tab.classList.remove("border-b-2", "border-mist-950", "text-mist-950", "dark:border-white", "dark:text-white")
        tab.classList.add("text-mist-500", "dark:text-mist-400", "hover:text-mist-700", "dark:hover:text-mist-300")
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

    // Notify other controllers (e.g. cost_preview) that the active tab
    // changed so they can reset state tied to the previous source type.
    // Dispatches as `tab-switch:changed` and bubbles through the DOM.
    this.dispatch("changed", { detail: { selectedTab } })
  }
}
