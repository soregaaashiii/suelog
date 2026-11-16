# /Users/kawamuratakuya/dev/suelog/config/importmap.rb
# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"

pin "controllers", to: "controllers/index.js"
pin_all_from "app/javascript/controllers", under: "controllers", preload: false

pin "article_editor", preload: false
pin "trix", preload: false
pin "@rails/actiontext", to: "actiontext.esm.js", preload: false

pin "hero_fit", to: "hero_fit.js"