// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {
  static targets = ["select", "esignEmails"]

  connect() {
    // Initialize Select2 on the <select> element
    this.initializeSelect2()
  }

  disconnect() {
    // Clean up when navigating away
    $(this.selectTarget).select2("destroy")
  }

  initializeSelect2() {

    if(!this.hasSelectTarget) return;
    const el = this.selectTarget

    // Listen for the internal state change and re-dispatch a native `change`
    $(el).on("select2:select select2:unselect clear", () => {
      el.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }

  /**
   * Validates a comma-separated list of emails in the esign_emails field.
   * If any invalid emails are found:
   * 1. Sets a custom validity message on the input.
   * 2. Adds the 'field_with_errors' class to the surrounding '.form-group'.
   * 3. Disables the form's next and submit buttons.
   *
   * @param {Event} event - The input event triggering the validation.
   */
  checkValidEmails(event) {
    const input = event.target;
    // Split input value by commas and trim whitespace
    const emails = input.value.split(",").map(email => email.trim());
    // Basic email validation regex
    const emailRegex = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

    // Filter out invalid emails (ignore empty strings)
    const invalidEmails = emails.filter(email => email !== "" && !emailRegex.test(email));
    const formGroup = input.closest(".form-group");
    const form = input.closest("form");
    // Find all potential submission/navigation buttons in the form
    const buttons = form ? form.querySelectorAll(".nextBtn, button[type='submit'], input[type='submit']") : [];

    if (invalidEmails.length > 0) {
      // Set error state
      input.setCustomValidity(`Invalid emails: ${invalidEmails.join(", ")}`);
      if (formGroup) {
        formGroup.classList.add("field_with_errors");
      }
      // Disable navigation/submission until resolved
      buttons.forEach(btn => btn.disabled = true);
    } else {
      // Clear error state
      input.setCustomValidity("");
      if (formGroup) {
        formGroup.classList.remove("field_with_errors");
      }
      // Re-enable navigation/submission
      buttons.forEach(btn => btn.disabled = false);
    }

    // Trigger browser's native validation UI
    input.reportValidity();
  }

  kyc_type_changed(event) {
    let kyc_type = $('#kyc_type').val();
    console.log("kyc_type", kyc_type);

    let href = new URL(window.location.href);
    href.searchParams.set('kyc_type', kyc_type);
    console.log(href.toString());

    window.location.href = href.toString();
  }

  investor_selected(event) {
    // Selec the display value not the id
    let selectedOption = event.target.options[event.target.selectedIndex];
    console.log("selectedOption", selectedOption);
    // Set the full name input field with the selected option's text, only if the kyc type is individual
    $("#individual_kyc_full_name").val(selectedOption.text);
  }

}
