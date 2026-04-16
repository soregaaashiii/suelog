// /Users/kawamuratakuya/dev/suelog/app/javascript/controllers/index.js
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

eagerLoadControllersFrom("controllers", application)

console.log("[stimulus] controllers loaded")