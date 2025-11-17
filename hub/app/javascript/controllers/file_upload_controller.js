import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "filename"]

  connect() {
    this.updateFilename()
  }

  triggerInput() {
    this.inputTarget.click()
  }

  handleDragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-[var(--color-primary)]")
  }

  handleDragLeave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-[var(--color-primary)]")
  }

  handleDrop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-[var(--color-primary)]")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.inputTarget.files = files
      this.updateFilename()
    }
  }

  updateFilename() {
    if (this.inputTarget.files.length > 0) {
      const filename = this.inputTarget.files[0].name
      this.filenameTarget.textContent = filename
      this.filenameTarget.classList.remove("hidden")
    } else {
      this.filenameTarget.classList.add("hidden")
    }
  }
}
