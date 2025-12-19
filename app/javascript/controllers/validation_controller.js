import { Controller } from "@hotwired/stimulus"

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

    validateFields(curInputs) {
        console.log("ValidationController: Validating fields");
        let clientSideValidations = this.element.ClientSideValidations;

        if (!clientSideValidations && curInputs.length > 0) {
            const form = $(curInputs[0]).closest('form')[0];
            if (form) {
                clientSideValidations = form.ClientSideValidations;
            }
        }

        if (!clientSideValidations) {
            const form = $(this.element).find("form[data-client-side-validations]")[0];
            if (form) {
                clientSideValidations = form.ClientSideValidations;
            }
        }

        if (!clientSideValidations || !clientSideValidations.settings || !clientSideValidations.settings.validators) {
            console.warn("ClientSideValidations settings or validators not found");
            return true;
        }

        let validators = clientSideValidations.settings.validators;
        let isValid = true;
        // $(".field_with_errors").removeClass("field_with_errors");

        for (var i = 0; i < curInputs.length; i++) {
            console.log(`Validating: ${$(curInputs[i]).attr("id")}`);
            console.log(validators);
            let input_type = $(curInputs[i]).attr("type");
            let input_id = $(curInputs[i]).attr("id");
            let jq_input_id = `#${input_id}`;

            if (!$(curInputs[i]).hasClass("custom_field") && !$(curInputs[i]).isValid(validators)) {

                // For Uppy file uploads, we check the hidden field which stores the uploaded file data
                if (input_type == "file") {
                    const resultField = $(curInputs[i]).closest('[data-controller="single-upload"]').find('input[data-single-upload-target="result"]');
                    if (resultField.length > 0 && resultField.val()) {
                        isInputValid = true;
                    }
                }
                else {
                    console.log(`Not valid custom_field: ${input_id} ${input_type}`);
                    isValid = false;
                }
            } else if ( input_type == "file" || $(curInputs[i]).hasClass("custom_field")) {
                // Special handling for file inputs created by us using _file.html.erb
                // And for custom fields which are not under client_side_validations perview
                let isInputValid = curInputs[i].validity.valid;

                // For Uppy file uploads, we check the hidden field which stores the uploaded file data
                if (input_type == "file") {
                    const resultField = $(curInputs[i]).closest('[data-controller="single-upload"]').find('input[data-single-upload-target="result"]');
                    if (resultField.length > 0 && resultField.val()) {
                        isInputValid = true;
                    }
                }

                if(!isInputValid) {
                    console.log(`Not valid: ${input_id} ${input_type}`);
                    isValid = false;
                    $(jq_input_id).closest(".form-group").addClass("field_with_errors");
                } else {
                    $(jq_input_id).closest(".form-group").removeClass("field_with_errors");
                }
            }

        }

        return isValid;
    }
}