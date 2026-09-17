# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "@rails--actiontext.js" # @8.1.300
pin "chartkick", to: "chartkick.js"
pin "@rails/activestorage", to: "activestorage.esm.js"

pin "@client-side-validations/client-side-validations/src", to: "/js/client_side_validations.js"
pin "@nathanvda/cocoon", to: "cocoon.min.js"
pin_all_from "app/javascript/custom", under: "custom"
pin "@rails/request.js", to: "request.js"
pin "turbo_progress_bar"
pin "countup.js" # @2.10.1
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/channels", under: "channels"

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
pin "highcharts/modules/sankey", to: "highcharts-sankey.js"
pin "highcharts/modules/heatmap", to: "highcharts-heatmap.js"
pin "highcharts/modules/funnel", to: "highcharts-funnel.js"
pin "highcharts/modules/accessibility", to: "highcharts-accessibility.js"

# config/importmap.rb
# Remove ANY pins for "chart.js/auto"
pin "chart.js", preload: true # @4.5.1
pin "xlsx", to: "xlsx.js" # @0.20.3 (SheetJS CDN build; npm is stuck at 0.18.5)
pin "pptxgenjs" # @4.0.1
pin "reveal.js" # @5.2.1
pin "reveal.js/plugin/highlight/highlight.esm.js", to: "reveal.js--plugin--highlight--highlight.esm.js.js" # @5.2.1
pin "reveal.js/plugin/markdown/markdown.esm.js", to: "reveal.js--plugin--markdown--markdown.esm.js.js" # @5.2.1
pin "reveal.js/plugin/notes/notes.esm.js", to: "reveal.js--plugin--notes--notes.esm.js.js" # @5.2.1
pin "dompurify" # @3.4.12
pin "marked" # @18.0.7
pin "mermaid", to: "https://cdn.jsdelivr.net/npm/mermaid@11.16.0/dist/mermaid.esm.min.mjs"
pin "node:fs" # @2.1.0
pin "node:https" # @2.1.0
pin "chartjs-plugin-datalabels" # @2.2.0
pin "chart.js/helpers", to: "chart.js--helpers.js" # @4.5.1
