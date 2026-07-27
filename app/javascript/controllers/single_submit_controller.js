import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { submitSelector: String }

  connect() {
    this.enterPending = false
    this.submissionStarted = false
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.isComposing) return

    const target = event.target
    const tagName = target.tagName.toLowerCase()

    if (tagName === "textarea" || tagName === "button" || target.type === "submit") return

    const submitButton = this.element.querySelector(this.submitSelectorValue)
    if (!submitButton) return

    event.preventDefault()
    if (this.enterPending || this.submissionStarted) return

    this.enterPending = true
    submitButton.click()

    window.setTimeout(() => {
      if (!this.submissionStarted) this.enterPending = false
    }, 0)
  }

  guardSubmit(event) {
    if (this.submissionStarted) {
      event.preventDefault()
      event.stopImmediatePropagation()
      return
    }

    this.submissionStarted = true
    this.enterPending = true

    window.setTimeout(() => {
      event.target.querySelectorAll('button[type="submit"], input[type="submit"]').forEach((control) => {
        control.disabled = true
      })
    }, 0)
  }
}
