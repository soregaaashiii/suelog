// /Users/kawamuratakuya/dev/suelog/app/javascript/controllers/index.js
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import "../hero_fit"

eagerLoadControllersFrom("controllers", application)

console.log("[stimulus] controllers loaded")