import  ValidationController from "controllers/validation_controller"
export default class extends ValidationController {
    
    validateSection(elem, validateFields) {
        console.log("Validating form section");
        $("form").enableClientSideValidations();
        $("form").removeAttr("novalidate");

        let isValid = true;
        let curInputs = $("form").find("input[type='checkbox'],input[type='file'],input[type='text'],input[type='number'],input[type='date'],select,textarea");
            
        if($("form").attr("data-client-side-validations")) {
            if ( $("form")[0].ClientSideValidations ) {
                isValid = validateFields(curInputs);
                console.log(`isValid = ${isValid}`);
            } else {
                console.log("No client side validations 1");
            }
        } else {
            console.log("No client side validations 2");            
        }

    }

}