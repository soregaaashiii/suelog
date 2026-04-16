// /Users/kawamuratakuya/dev/suelog/app/javascript/controllers/application.js
import { Application } from "@hotwired/stimulus"
import "../hero_fit"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

export { application }