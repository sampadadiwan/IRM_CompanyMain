# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "@rails--actiontext.js" # @8.0.200
pin "chartkick", to: "chartkick.js"
pin "@rails/activestorage", to: "activestorage.esm.js"

pin "@client-side-validations/client-side-validations/src", to: "/js/client_side_validations.js"
pin "@nathanvda/cocoon", to: "cocoon.min.js"
pin_all_from "app/javascript/custom", under: "custom"
pin "@rails/request.js", to: "request.js"
pin "turbo_progress_bar"
pin "countup.js" # @2.8.0
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/channels", under: "channels"

pin "uppy", to: "uppy.min.js"

pin "moment" # @2.30.1
pin "typeahead" # @0.2.2
pin "dom" # @0.0.2
pin "xtend" # @1.0.3
pin "sortable" # @2.0.0
pin "jquery-browserify" # @1.8.1
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"

# Bootstrap tooltips (used by controllers/tooltip_controller)
pin "@popperjs/core", to: "https://cdn.jsdelivr.net/npm/@popperjs/core@2.11.8/+esm", preload: true
pin "bootstrap", to: "/modernize/libs/bootstrap/dist/js/bootstrap.esm.min.js", preload: true

pin "highcharts", to: "highcharts.js"
pin "highcharts-more", to: "highcharts-more.js"
pin "highcharts/modules/exporting", to: "highcharts-exporting.js"
pin "highcharts/modules/offline-exporting", to: "highcharts-offline-exporting.js"

# config/importmap.rb
# Remove ANY pins for "chart.js/auto"
pin "chart.js", to: "chart.js", preload: true
pin "xlsx", to: "xlsx.js"
pin "pptxgenjs", to: "pptxgenjs.js"
pin "reveal.js" # @5.2.1
pin "reveal.js/plugin/highlight/highlight.esm.js", to: "reveal.js--plugin--highlight--highlight.esm.js.js" # @5.2.1
pin "reveal.js/plugin/markdown/markdown.esm.js", to: "reveal.js--plugin--markdown--markdown.esm.js.js" # @5.2.1
pin "reveal.js/plugin/notes/notes.esm.js", to: "reveal.js--plugin--notes--notes.esm.js.js" # @5.2.1
pin "dompurify" # @3.4.1
pin "marked" # @18.0.2
pin "mermaid", to: "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs"
