import  ValidationController from "controllers/validation_controller"
export default class extends ValidationController {

    initialize() {
        console.log("ValidationController: initialize called");
        console.log($(this.element));
        if ($(this.element).find("form[data-client-side-validations]").length > 0) {
            super.initialize()
        }
    }

    validateSection(elem, validateFields) {
        console.log("Validating form section");
        let form = $("form[data-client-side-validations]");
        form.enableClientSideValidations();
        form.removeAttr("novalidate");

        let isValid = true;
        let curInputs = form.find("input[type='checkbox'],input[type='file'],input[type='text'],input[type='number'],input[type='date'],select,textarea");

        console.log(`Form to validate: ` + form);
        console.log(`Current inputs: ` + curInputs.length);

        if(form.attr("data-client-side-validations")) {
            console.log(`Client side validations found for ` + form);
            if ( form[0].ClientSideValidations ) {
                isValid = validateFields(curInputs);
                console.log(`isValid = ${isValid}`);
            } else {
                console.log("No client side validations 1");
            }
        } else {
            console.log("No client side validations 2");
        }

        if (!isValid) {
            this.showErrorModal("Please correct the errors on the form before proceeding.");
        }

        return isValid;
    }

    showErrorModal(message) {
        // Check if modal already exists and is shown
        if ($('#validationErrorModal').hasClass('show')) {
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

}