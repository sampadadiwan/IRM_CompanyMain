import { Controller } from "@hotwired/stimulus"
import { isIP } from "net";

export default class ValidationController extends Controller {
    initialize() {
        this.init();
    }

    connect() {
        $(this.element).filter("form[data-client-side-validations]").enableClientSideValidations();
        console.log("validation controller connected");
    }

    init() {
        let submitBtn = $(this.element).find("input[type='submit']");
        submitBtn.off("click.validation").on("click.validation", (e) => {
            const isValid = this.validateSection(e.currentTarget, this.validateFields.bind(this));
            if (!isValid) {
                e.preventDefault();
            }
        });

        this.disable_number_field_arrows();
    }

    disable_number_field_arrows() {
        // Remove arrow up and down from number fields
        this.element.querySelectorAll('input[type=number]').forEach(function(input) {

            input.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
                e.preventDefault();
            }
            });

            // Disable scroll wheel
            input.addEventListener('wheel', function(e) {
            e.preventDefault();
            });
      });
    }

    /**
     * Validates a set of input fields using ClientSideValidations and custom logic.
     *
     * This method handles:
     * 1. Locating the ClientSideValidations configuration from the form.
     * 2. Iterating through provided inputs.
     * 3. Validating standard fields using the rails-client-side-validations plugin.
     * 4. Special handling for file uploads (specifically Uppy/SingleUpload controller).
     * 5. Special handling for "custom_field" inputs that might not be tracked by standard validations.
     * 6. Updating the UI by toggling the "field_with_errors" class on the parent form group.
     *
     * @param {Array|jQuery} curInputs - The collection of input elements to validate.
     * @returns {boolean} - Returns true if all fields are valid, false otherwise.
     */
    validateFields(curInputs) {
        console.log("ValidationController: Validating fields");
        let clientSideValidations = this.element.ClientSideValidations;

        // Attempt to find ClientSideValidations if not directly on this.element
        // This often happens when the controller is on a wrapper but the form is nested
        if (!clientSideValidations && curInputs.length > 0) {
            const form = $(curInputs[0]).closest('form')[0];
            if (form) {
                clientSideValidations = form.ClientSideValidations;
            }
        }

        // Fallback: look for any form with client-side validations inside the element
        if (!clientSideValidations) {
            const form = $(this.element).find("form[data-client-side-validations]")[0];
            if (form) {
                clientSideValidations = form.ClientSideValidations;
            }
        }

        // If no validation settings are found, assume valid to avoid blocking submission
        if (!clientSideValidations || !clientSideValidations.settings || !clientSideValidations.settings.validators) {
            console.warn("ClientSideValidations settings or validators not found");
            return true;
        }

        let validators = clientSideValidations.settings.validators;
        let isValid = true;

        for (var i = 0; i < curInputs.length; i++) {
            let input_id = $(curInputs[i]).attr("id");

            if(input_id) {
                console.log(`Validating: ${input_id}`);
                let input_type = $(curInputs[i]).attr("type");
                let jq_input_id = `#${input_id}`;
                let isInputValid = true;

                // Scenario 1: Standard field (not a custom_field)
                // We use the .isValid(validators) method provided by rails-client-side-validations
                if (!$(curInputs[i]).hasClass("custom_field") && !$(curInputs[i]).isValid(validators)) {

                    // Special Case: Uppy/SingleUpload file inputs
                    // The standard file input might look invalid because it's technically empty (browser security),
                    // so we check the hidden result field where the uploaded file metadata is stored.
                    if (input_type == "file") {
                        const resultField = $(curInputs[i]).closest('[data-controller="single-upload"]').find('input[data-single-upload-target="result"]');
                        if (resultField.length > 0 && resultField.val()) {
                            console.log(`Valid Uppy file upload: ${input_id} ${input_type} 1`);
                            isInputValid = true;
                        } else {
                            isInputValid = false;
                            console.log(`Not valid 1: ${input_id} ${input_type}`);
                        }
                    }
                    else {
                        console.log(`Not valid 1: ${input_id} ${input_type}`);
                        isValid = false;
                    }
                }
                // Scenario 2: File inputs or Custom fields that fail initial validation check
                else if ( (input_type == "file" || $(curInputs[i]).hasClass("custom_field")) && !$(curInputs[i]).isValid(validators) ) {
                    // Fallback to native browser validation if CSV fails or doesn't cover it
                    isInputValid = curInputs[i].validity.valid;

                    // Re-check Uppy file upload status for these special cases
                    if (input_type == "file") {
                        const resultField = $(curInputs[i]).closest('[data-controller="single-upload"]').find('input[data-single-upload-target="result"]');
                        if (resultField.length > 0 && resultField.val()) {
                            console.log(`Valid Uppy file upload: ${input_id} ${input_type} 2`);
                            isInputValid = true;
                        } else {
                            console.log(`Not valid 2: ${input_id} ${input_type}`);
                            isInputValid = false;
                        }
                    }
                }

                // UI Update: Apply or remove error styling based on validation result
                if(!isInputValid) {
                    console.log(`Not valid: ${input_id} ${input_type}`);
                    isValid = false;
                    $(jq_input_id).closest(".form-group").addClass("field_with_errors");
                } else if (input_id) {
                    $(jq_input_id).closest(".form-group").removeClass("field_with_errors");
                }
            } else {
                console.warn("Skipping Input without ID during validation");
            }
        }

        return isValid;
    }
}