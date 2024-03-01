# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "actiontext.js"
pin "chartkick", to: "chartkick.js"
pin "@rails/activestorage", to: "activestorage.esm.js"

pin "@client-side-validations/client-side-validations/src", to: "/js/client_side_validations.js"
pin "@nathanvda/cocoon", to: "cocoon.min.js"
pin_all_from "app/javascript/custom", under: "custom"
pin "@rails/request.js", to: "request.js"
pin "turbo_progress_bar"
pin "countup.js" # @2.8.0
