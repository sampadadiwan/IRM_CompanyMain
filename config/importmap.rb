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

pin "highcharts",                         to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/highcharts.src.js"
pin "highcharts-more",                    to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/highcharts-more.src.js"
pin "highcharts/modules/exporting",       to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/modules/exporting.src.js"
pin "highcharts/modules/offline-exporting", to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/modules/offline-exporting.src.js"

# config/importmap.rb
# Remove ANY pins for "chart.js/auto"
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.4/+esm", preload: true
pin "xlsx", to: "https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"
pin "pptxgenjs", to: "https://cdn.jsdelivr.net/npm/pptxgenjs@4.0.0/+esm"
