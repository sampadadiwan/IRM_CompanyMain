import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.initialize();
        $(".wizard_form").enableClientSideValidations();
        console.log("Wizard controller connected");
    }

    initialize() {
        console.log("WizardController: initialize called");
        let validateFields = this.validateFields.bind(this);
        let validateSection = this.validateSection.bind(this);

        let submitBtn = $(".wizard_form").find("input[type='submit']");
        submitBtn.off("click").on("click", function (e) {
            console.log("WizardController: submitBtn clicked");
            validateSection(this, validateFields);
        });

        var navListItems = $('div.setup-panel div a'),
            allWells = $('.setup-content'),
            allNextBtn = $('.nextBtn');

        allWells.hide();

        navListItems.off("click").on("click", function (e) {
            e.preventDefault();
            console.log("WizardController: navListItem clicked", $(this).attr('href'));
            var $target = $($(this).attr('href')),
                $item = $(this);

            if (!$item.hasClass('disabled')) {
                navListItems.removeClass('btn-primary').addClass('btn-default');
                $item.addClass('btn-primary');
                allWells.hide();
                $target.show();
                $target.find('input:eq(0)').focus();
            }
        });

        allNextBtn.off("click").on("click", function () {
            console.log("WizardController: nextBtn clicked");
            validateSection(this, validateFields);
        });

        $('div.setup-panel div a.btn-outline-primary').first().trigger('click');
    }

    validateSection(elem, validateFields) {
        console.log("WizardController: validateSection called", elem);
        $(".wizard_form").enableClientSideValidations();
        $(".wizard_form").removeAttr("novalidate");

        let isValid = true;
        var curStep = $(elem).closest(".setup-content"),
            curStepBtn = curStep.attr("id"),
            nextStepWizard = $('div.setup-panel div a[href="#' + curStepBtn + '"]').parent().next().children("a"),
            curInputs = curStep.find("input[type='checkbox'],input[type='file'],input[type='text'],input[type='number'],input[type='date'],select,textarea");

        let investorInput = $(".wizard_form").find("select[id$='_kyc_investor_id']");
        let investorFormGroup = investorInput.closest(".form-group");

        if ($(".wizard_form").attr("data-client-side-validations")) {
            if ($(".wizard_form")[0].ClientSideValidations) {
                isValid = validateFields(curInputs);
            }
        } else {
            console.log("No client side validations");

            if (investorInput.length) {
                // remove old error messages
                investorFormGroup.find(".help-block.error").remove();

                if (!investorInput.val()) {
                    isValid = false;
                    investorFormGroup.addClass("field_with_errors");

                    // inject message like Rails client_side_validations does
                    investorFormGroup.append('<span class="help-block error"><strong>can\'t be blank</strong></span>');

                    $('html, body').animate({ scrollTop: investorInput.offset().top - 140 }, 100);
                } else {
                    investorFormGroup.removeClass("field_with_errors");
                }
            }
        }

        console.log("WizardController: isValid =", isValid);
        if (isValid) {
            nextStepWizard.removeClass('disabled').trigger('click');
        } else {
            this.showErrorModal("Please correct the errors on the form before proceeding.");
        }
    }

    showErrorModal(message) {
        console.log("WizardController: showErrorModal called", message);
        // Check if modal already exists and is shown
        if ($('#validationErrorModal').hasClass('show')) {
            console.log("WizardController: modal already showing, skipping");
            return;
        }

        // Remove any existing modals to avoid stacking them
        $('#validationErrorModal').remove();

        const modalElement = `
            <div class="modal fade" id="validationErrorModal" tabindex="-1" aria-labelledby="validationErrorModalLabel" aria-hidden="true">
                <div class="modal-dialog">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h5 class="modal-title" id="validationErrorModalLabel">Validation Error</h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                        </div>
                        <div class="modal-body">
                            ${message}
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        $('body').append(modalElement);

        const modal = new bootstrap.Modal(document.getElementById('validationErrorModal'));
        modal.show();
    }


    validateFields(curInputs) {
        let validators = $(".wizard_form")[0].ClientSideValidations.settings.validators;
        let isValid = true;
        // $(".field_with_errors").removeClass("field_with_errors");

        for (var i = 0; i < curInputs.length; i++) {
            // console.log(`Validating: ${$(curInputs[i]).attr("id")}`);
            let input_type = $(curInputs[i]).attr("type");
            let input_id = $(curInputs[i]).attr("id");
            let jq_input_id = `#${input_id}`;

            if (!$(curInputs[i]).hasClass("custom_field") && !$(curInputs[i]).isValid(validators)) {
                console.log(`Not valid: ${input_id} ${input_type}`);
                isValid = false;
            } else if (input_type == "file" || $(curInputs[i]).hasClass("custom_field")) {
                // Special handling for file inputs created by us using _file.html.erb
                // And for custom fields which are not under client_side_validations perview
                if (!curInputs[i].validity.valid) {
                    console.log(`Not valid: ${input_id} ${input_type}`);
                    isValid = false;
                    $(jq_input_id).closest(".form-group").addClass("field_with_errors");
                    scrollTop: $(jq_input_id).focus();
                    $('html, body').animate({
                        scrollTop: $(jq_input_id).offset().top - 140
                    }, 100);

                } else {
                    $(jq_input_id).closest(".form-group").removeClass("field_with_errors");
                }
            }

        }

        return isValid;
    }


    close(event) {
        console.log("closeForm");
        $(".dynamic_form").remove();
    }
}
