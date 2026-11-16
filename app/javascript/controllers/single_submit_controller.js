import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { submitSelector: String, deferUntilTurbo: Boolean, confirmMessage: String }

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

    // Turbo asks for confirmation after the submit event. Do not lock the
    // form until it actually starts, otherwise Cancel leaves it locked forever.
    if (this.deferUntilTurboValue) return
    if (this.confirmMessageValue && !window.confirm(this.confirmMessageValue)) {
      event.preventDefault()
      this.enterPending = false
      return
    }
    this.startSubmission()
  }

  startSubmission() {
    this.submissionStarted = true
    this.enterPending = true

    window.setTimeout(() => {
      this.element.querySelectorAll('button[type="submit"], input[type="submit"]').forEach((control) => {
        control.disabled = true
      })
    }, 0)
  }

  finishSubmission() {
    this.submissionStarted = false
    this.enterPending = false
    this.element.querySelectorAll('button[type="submit"], input[type="submit"]').forEach(control => { control.disabled = false })
  }
}
