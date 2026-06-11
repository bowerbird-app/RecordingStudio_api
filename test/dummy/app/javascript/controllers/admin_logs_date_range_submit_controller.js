import { Controller } from "@hotwired/stimulus"

// Submits the logs filter form only when the FlatPack date picker Apply action is clicked.
export default class extends Controller {
  submitOnApply(event) {
    const applyButton = event.target.closest("[data-flat-pack-date-picker-command='apply']")
    if (!applyButton) {
      return
    }

    requestAnimationFrame(() => {
      this.element.requestSubmit()
    })
  }
}
