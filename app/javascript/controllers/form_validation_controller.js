import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.init();
        $(".validate_form").enableClientSideValidations();
        console.log("form validation controller connected");
    }

    init() {
        
        let validateFields = this.validateFields;
        let validateSection = this.validateSection;

        let submitBtn = $(".validate_form").find("input[type='submit']");
        submitBtn.click(function(e) {
            validateSection(this, validateFields);
        });
     
    }

    validateSection(elem, validateFields) {
        console.log("Validating form section");
        $(".validate_form").enableClientSideValidations();
        $(".validate_form").removeAttr("novalidate");

        let isValid = true;
        let curInputs = $(".validate_form").find("input[type='checkbox'],input[type='file'],input[type='text'],input[type='number'],input[type='date'],select,textarea");
            
        if($(".validate_form").attr("data-client-side-validations")) {
            if ( $(".validate_form")[0].ClientSideValidations ) {
                isValid = validateFields(curInputs);
                console.log(`isValid = ${isValid}`);
                console.log(curInputs);
            } else {
                console.log("No client side validations 1");
            }
        } else {
            console.log("No client side validations 2");            
        }

    }


    validateFields(curInputs) {
        let validators = $(".validate_form")[0].ClientSideValidations.settings.validators;
        let isValid = true;        
        // $(".field_with_errors").removeClass("field_with_errors");
        
        for (var i = 0; i < curInputs.length; i++) {
            console.log(`Validating: ${$(curInputs[i]).attr("id")}`);
            let input_type = $(curInputs[i]).attr("type");
            let input_id = $(curInputs[i]).attr("id");
            let jq_input_id = `#${input_id}`;

            if (!$(curInputs[i]).hasClass("custom_field") && !$(curInputs[i]).isValid(validators)) {
                console.log(`Not valid: ${input_id} ${input_type}`);
                isValid = false;
            } else if ( input_type == "file" || $(curInputs[i]).hasClass("custom_field")) {
                // Special handling for file inputs created by us using _file.html.erb
                // And for custom fields which are not under client_side_validations perview
                if(!curInputs[i].validity.valid) {
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