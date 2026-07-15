import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]
  static values = { delay: { type: Number, default: 0 } }

  connect() {
    if (!this.hasLinkTarget || this.observer) return

    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting || this.clicked) return

        this.clicked = true
        window.setTimeout(() => this.linkTarget.click(), this.delayValue)
        this.disconnectObserver()
      })
    }, { rootMargin: "200px 0px" })

    this.observer.observe(this.element)
  }

  disconnect() {
    this.disconnectObserver()
  }

  disconnectObserver() {
    if (!this.observer) return

    this.observer.disconnect()
    this.observer = null
  }
}