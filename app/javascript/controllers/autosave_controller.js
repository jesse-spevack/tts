import { Controller } from "@hotwired/stimulus"

// Submits the parent form as soon as an input changes.
// Server redirect + flash banner provides the feedback.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
