// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "@rails/actiontext"
import "@rails/activestorage"
import "trix"
import "controllers"
import "channels"
import "chartkick"
import '@client-side-validations/client-side-validations/src'
import "@nathanvda/cocoon"
import "turbo_progress_bar"


import "vega"
import "vega-lite"
import "vega-embed"

window.dispatchEvent(new Event("vega:load"))

Highcharts.setOptions({
  lang: {
    thousandsSep: ',',
    decimalPoint: '.'
  }
});

$('.select2').select2();

document.addEventListener("turbo:load", () => {
  document.querySelectorAll("action-text-attachment").forEach(el => {
    if (!el.querySelector("img") && el.hasAttribute("url")) {
      const img = document.createElement("img")
      img.src = el.getAttribute("url")
      img.width = el.getAttribute("width")
      img.height = el.getAttribute("height")
      el.querySelector("figure")?.prepend(img)
    }
  })
});


// Handle select2 on turbolinks
$(document).on('turbo:before-cache', function() {

  console.log("turbo:before-cache called");

  if( $('.select2-container').length > 0 ){
    // Hack to make sure select2 does not get duplicated due to turbolinks
    $('#investor_investor_entity_id').select2('destroy');
    $('#investment_investor_id').select2('destroy');
    $('#deal_investor_investor_id').select2('destroy');
    $('#folder_parent_id').select2('destroy');
    $('#document_folder_id').select2('destroy');
    $('#access_right_access_to_category').select2('destroy');
    $('#access_right_access_to_investor_id').select2('destroy');
  }

});

$( document ).on('turbo:load', function() {

    console.log("turbo:load called");

    if (document.location.hostname.search("localhost") !== 0) {
      console.log("Google Analytics Enabled");
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-4CPQNX69HM');
    }

    $('.select2').select2();
    $(document).on('select2:open', () => {
      document.querySelector('.select2-search__field').focus();
    });

    // data-simplebar
    $(".data-simplebar").each(function() {
      new SimpleBar(this);
    });    

    "use strict";
});

