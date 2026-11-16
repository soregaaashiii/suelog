// /Users/kawamuratakuya/dev/suelog/app/javascript/controllers/index.js
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"

lazyLoadControllersFrom("controllers", application)

console.log("[stimulus] controllers loaded")