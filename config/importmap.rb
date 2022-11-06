# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "actiontext.js"
pin "@popperjs/core", to: "https://cdnjs.cloudflare.com/ajax/libs/popper.js/2.9.2/umd/popper.min.js"
pin "chartkick", to: "chartkick.js"
# pin "Chart.bundle", to: "Chart.bundle.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "highcharts" # @10.0.0
pin "chartkick", to: "chartkick.js"

pin "@client-side-validations/client-side-validations/src", to: "/js/client_side_validations.js"
pin "@nathanvda/cocoon", to: "https://cdn.jsdelivr.net/npm/@nathanvda/cocoon@1.2.14/cocoon.min.js"
pin_all_from "app/javascript/custom", under: "custom"
