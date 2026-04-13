/**
 * Global Select2 initialization and event handling.
 * Handles Turbo integration, multi-select ordering, and focus management.
 */

/**
 * Initializes Select2 on all elements with the .select2 class within the given root.
 * Ensures compatibility with Bootstrap modals and preserves selection order for multi-selects.
 *
 * @param {HTMLElement|Document} root - The root element to search for .select2 elements.
 */
export function initSelect2(root = document) {
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

// Global handler for multi-select ordering
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
document.addEventListener('turbo:frame-load', (e) => {
  initSelect2(e.target);
});

// Important: tear down before Turbo caches the page,
// otherwise re-visits can double-initialize or break the UI
// document.addEventListener('turbo:before-cache', () => {
//   $('select.select2').each(function () {
//     if ($(this).data('select2')) $(this).select2('destroy');
//   });

//   if ($('.select2-container').length > 0) {
//     // Hack to make sure select2 does not get duplicated due to turbolinks/turbo
//     const idsToDestroy = [
//       '#investor_investor_entity_id',
//       '#investment_investor_id',
//       '#deal_investor_investor_id',
//       '#folder_parent_id',
//       '#document_folder_id',
//       '#access_right_access_to_category',
//       '#access_right_access_to_investor_id'
//     ];
//     idsToDestroy.forEach(id => $(id).select2('destroy'));
//   }
// });

// Important: tear down Select2 before Turbo caches the page on a real navigation
// (not hash/anchor changes which fire before-cache without a subsequent render).
// We only destroy if the new URL differs in path/search, not just hash.
document.addEventListener('turbo:before-cache', () => {
  const current = new URL(location.href);
  const cached = new URL(document.location.href);
  const isHashOnly = current.pathname === cached.pathname && current.search === cached.search;
  if (isHashOnly) return;

  // Destroy all select2 instances generically
  $('select.select2').each(function () {
    if ($(this).data('select2')) $(this).select2('destroy');
  });

});

$(document).on('turbo:load', function () {

  initSelect2();

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
});
