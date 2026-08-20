import { Controller } from "@hotwired/stimulus"

const DATE_TYPES = ["date", "datetime", "timestamp"];

export default class extends Controller {
  static values = { attributeTypes: Object }

  connect() {
    console.log("filter connect");
    $('form').on('click', '.remove_fields', function(event) {
        $(this).closest('.row').remove();
        event.preventDefault();
    });
    $('form').on('click', '.add_fields', function(event) {
        var time = new Date().getTime();
        var regexp = new RegExp($(this).data('id'), 'g');

        // console.log(`regexp: ${regexp}`);
        // console.log(`$(this).data('fields'): ${$(this).data('fields')}`);

        $(this).parent().before($(this).data('fields').replace(regexp, time));
        event.preventDefault();
    });
    $('form').on('change', '.attribute-select', (event) => {
        this.toggleValueField(event.target);
    });
  }

  // Swaps a condition row's value input between the plain text field and the
  // locale-date widget depending on the newly selected attribute's column type.
  // Only one of the two inputs is left enabled so exactly one `value` param submits.
  toggleValueField(select) {
    const row = select.closest('.row');
    if (!row) return;

    const textWrapper = row.querySelector('.value-field-text');
    const dateWrapper = row.querySelector('.value-field-date');
    if (!textWrapper || !dateWrapper) return;

    // textInput/hiddenInput are the two elements the disabled-toggle invariant below
    // depends on (exactly one enabled so exactly one `value` param submits) — bail
    // out rather than risk leaving both/neither enabled if either is missing.
    const textInput = textWrapper.querySelector('input');
    const hiddenInput = dateWrapper.querySelector('[data-locale-date-target="hidden"]');
    if (!textInput || !hiddenInput) return;

    const isDate = DATE_TYPES.includes(this.attributeTypesValue[select.value]);

    textWrapper.classList.toggle('d-none', isDate);
    dateWrapper.classList.toggle('d-none', !isDate);

    const displayInput = dateWrapper.querySelector('[data-locale-date-target="display"]');
    const pickerInput = dateWrapper.querySelector('[data-locale-date-target="picker"]');

    textInput.disabled = isDate;
    hiddenInput.disabled = !isDate;

    // Clear whatever the previous attribute's value was — it doesn't carry meaning
    // for the newly selected attribute.
    textInput.value = "";
    hiddenInput.value = "";
    if (displayInput) displayInput.value = "";
    if (pickerInput) pickerInput.value = "";
  }
}


