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

import Highcharts from "highcharts"
import "highcharts-more"
import "highcharts/modules/exporting"
import "highcharts/modules/offline-exporting"

window.bootstrap = bootstrap
window.Highcharts = Highcharts

Highcharts.setOptions({
  lang: {
    thousandsSep: ',',
    decimalPoint: '.'
  }
});


function initSelect2(root = document) {
  $(root).find('select.select2').each(function () {
    // Skip if already initialized by Select2
    if ($(this).hasClass('select2-hidden-accessible')) return;

    // If used in a Bootstrap modal, ensure the dropdown renders inside it
    const $parentModal = $(this).closest('.modal');
    const $el = $(this);
    $el.select2({
      width: 'resolve',
      dropdownParent: $parentModal.length ? $parentModal : $(document.body)
    });

    // Support for preserving selection order in multi-selects
    if ($el.attr('multiple')) {
      $el.on('select2:select', function (e) {
        const id = e.params.data.id;
        const option = $el.find(`option[value="${id}"]`);
        option.detach().appendTo($el);
        $el.trigger('change');
      });
    }
  });
}

$(document).on('select2:select', 'select[multiple]', function (e) {
  const element = e.params.data.element;
  if (!element) return;

  const $element = $(element);
  const $select = $(this);

  // Move selected option to the end to preserve selection order
  $element.detach();
  $select.append($element);

  // Notify Select2 of DOM change
  $select.trigger('change.select2');
});

// Initialize on normal Turbo renders
document.addEventListener('turbo:load', () => initSelect2());

// Initialize when a <turbo-frame> finishes loading
document.addEventListener('turbo:frame-load', (e) => initSelect2(e.target));

// Important: tear down before Turbo caches the page,
// otherwise re-visits can double-initialize or break the UI
document.addEventListener('turbo:before-cache', () => {
  $('select.select2').each(function () {
    if ($(this).data('select2')) $(this).select2('destroy');
  });
});

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
    // When any Select2 dropdown opens, only focus the search field inside
    // the dropdown that was just opened. Previously we always focused the
    // first `.select2-search__field` on the page which caused focus to jump
    // to other select inputs when multiple select2 elements existed.
    $(document).on('select2:open', (e) => {
      // The opened dropdown is appended to the body (or dropdownParent). Find
      // a search field inside the visible .select2-container--open instance.
      const containers = document.querySelectorAll('.select2-container--open');
      if (containers.length === 0) return;

      // Prefer the container that is associated with the element that triggered
      // the event. Select2 sets `aria-controls` on the original select which
      // matches the id of the dropdown. Try to find a matching container first.
      let targetSearch = null;
      try {
        const select = $(e.target);
        const dropdownId = select.data('select2')?.$dropdown?.attr('id');
        if (dropdownId) {
          const container = document.querySelector(`#${dropdownId}`).closest('.select2-container--open');
          if (container) {
            targetSearch = container.querySelector('.select2-search__field');
          }
        }
      } catch (err) {
        // ignore and fallback to other heuristics
      }

      // Fallback: focus the last opened container's search field (usually the
      // one most recently opened appears last in the DOM)
      if (!targetSearch) {
        const last = containers[containers.length - 1];
        targetSearch = last.querySelector('.select2-search__field');
      }

      if (targetSearch) targetSearch.focus();
    });

    // data-simplebar
    $(".data-simplebar").each(function() {
      new SimpleBar(this);
    });

    "use strict";
});
