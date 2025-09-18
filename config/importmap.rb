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

# For polars graphing
pin "vega", to: "vega.js"
pin "vega-lite", to: "vega-lite.js"
pin "vega-embed", to: "vega-embed.js"
pin "playwright" # @1.49.0
pin "assert" # @2.1.0
pin "async_hooks" # @2.1.0
pin "buffer" # @2.1.0
pin "bufferutil" # @4.0.8
pin "child_process" # @2.1.0
pin "chromium-bidi/lib/cjs/bidiMapper/BidiMapper", to: "chromium-bidi--lib--cjs--bidiMapper--BidiMapper.js" # @0.10.0
pin "chromium-bidi/lib/cjs/cdp/CdpConnection", to: "chromium-bidi--lib--cjs--cdp--CdpConnection.js" # @0.10.0
pin "constants" # @2.1.0
pin "crypto" # @2.1.0
pin "dns" # @2.1.0
pin "electron/index.js", to: "electron--index.js.js" # @33.2.0
pin "events" # @2.1.0
pin "fs" # @2.1.0
pin "http" # @2.1.0
pin "http2" # @2.1.0
pin "https" # @2.1.0
pin "inspector" # @2.1.0
pin "mitt" # @3.0.1
pin "module" # @2.1.0
pin "net" # @2.1.0
pin "node-gyp-build" # @4.8.4
pin "os" # @2.1.0
pin "path" # @2.1.0
pin "playwright-core" # @1.49.0
pin "process" # @2.1.0
pin "readline" # @2.1.0
pin "stream" # @2.1.0
pin "tls" # @2.1.0
pin "tty" # @2.1.0
pin "url" # @2.1.0
pin "urlpattern-polyfill" # @10.0.0
pin "utf-8-validate" # @6.0.5
pin "util" # @2.1.0
pin "zlib" # @2.1.0
pin "moment" # @2.30.1
pin "typeahead" # @0.2.2
pin "dom" # @0.0.2
pin "xtend" # @1.0.3
pin "sortable" # @2.0.0
pin "jquery-browserify" # @1.8.1
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "highcharts",                         to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/highcharts.src.js"
pin "highcharts-more",                    to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/highcharts-more.src.js"
pin "highcharts/modules/exporting",       to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/modules/exporting.src.js"
pin "highcharts/modules/offline-exporting", to: "https://cdn.jsdelivr.net/npm/highcharts@12.3.0/es-modules/masters/modules/offline-exporting.src.js"

# config/importmap.rb
# Remove ANY pins for "chart.js/auto"
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.4/+esm", preload: true
