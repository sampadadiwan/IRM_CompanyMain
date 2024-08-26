import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        this.change();        
    }

    change(event) {
        let email_method = $("#custom_notification_email_method").val().toLowerCase();
        console.log(`adhoc_notification_controller change ${email_method}`);
        if(email_method == "adhoc_notification"){
            $("#adhoc_notifications_to_form_group").show();
        }
        else {
            $("#adhoc_notifications_to_form_group").hide();  
        }
    }


}


