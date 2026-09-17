// No bundler needed: HTTP/2 multiplexing means many small files carry no material performance penalty vs one large bundle. Caching is also better — only changed files invalidate their cache entry. See: https://github.com/rails/importmap-rails
// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "@rails/actiontext"
import "@rails/activestorage"
import "trix"
import "controllers";

import "channels"
import "chartkick"
import '@client-side-validations/client-side-validations/src'
import "@nathanvda/cocoon"
import "turbo_progress_bar"
import * as bootstrap from "bootstrap"

// Custom Handlers (Modularized)
import "custom/charts_handler"
import "custom/select2_handler"
import "custom/turbo_handler"
import "custom/turbo_frame_error_handler"

window.bootstrap = bootstrap

// LocaleDateFormBuilder is the app's default form builder; register it as an alias so
// ClientSideValidations resolves the correct add/remove error handlers (it keys on the
// Ruby form builder class name stored in the form's data-client-side-validations attribute).
if (window.ClientSideValidations?.formBuilders) {
  ClientSideValidations.formBuilders["LocaleDateFormBuilder"] =
    ClientSideValidations.formBuilders["ActionView::Helpers::FormBuilder"]
}

/**
 * Global initialization for third-party scripts and UI components.
 */
document.addEventListener("turbo:load", () => {
  // Initialize ActionText attachments (ensure images are rendered)
  document.querySelectorAll("action-text-attachment").forEach(el => {
    if (!el.querySelector("img") && el.hasAttribute("url")) {
      const img = document.createElement("img")
      img.src = el.getAttribute("url")
      img.width = el.getAttribute("width")
      img.height = el.getAttribute("height")
      el.querySelector("figure")?.prepend(img)
    }
  })

  // Google Analytics in the authenticated app was removed deliberately: it tracked
  // signed-in fund staff and LP sessions, which the public cookie policy says the
  // signed-in application does not do. Don't reintroduce it without a privacy
  // review and a matching change to website_src/pages/cookies.html.

  // Initialize SimpleBar for custom scrollbars
  $(".data-simplebar").each(function() {
    new SimpleBar(this);
  });

  "use strict";
});
