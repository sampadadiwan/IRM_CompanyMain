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

window.bootstrap = bootstrap

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

  // Initialize Google Analytics (Production only)
  if (document.location.hostname.search("localhost") !== 0) {
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', 'G-4CPQNX69HM');
  }

  // Initialize SimpleBar for custom scrollbars
  $(".data-simplebar").each(function() {
    new SimpleBar(this);
  });

  "use strict";
});
