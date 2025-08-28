import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    connect() {
        console.log("confirm connect");
        if( $("#alertPopupModal").length ) {
            this.popup_status();
        }
    }

    popup(event) {
        let btn = $(event.target);
        let title = event.target.dataset.title || "Are you sure?";
        let method = event.target.dataset.method || "delete";
        let msg = event.target.dataset.msg || "This will permanently delete this item. Proceed?" ;
        let submitForm = event.target.dataset.submitForm;

        console.log(`btn.dataset.modalId: ${event.target.dataset.modalId}`);

        this.deleteForm = event.target.closest("form");

        $('#confirmModal #msg').html(msg);
        $('#confirmModal #title').text(title);
        $('#confirmModal #method').val(method);
        $('#confirmModal #submitForm').val(submitForm);

        // We set the action to the delete btn form action
        $("#confirm_submit").attr("action", this.deleteForm.action);

        // Now we need to set turbo on or off, depending on the buttons turbo setting
        $("#confirm_submit").attr("data-turbo", true);
        if(btn.attr("data-turbo") == "false") {
            $("#confirm_submit").attr("data-turbo", false);
        }

        // Finally we need the authenticity token from the delete btn form
        let at = $(this.deleteForm).find('input[name="authenticity_token"]').val();
        $("#confirm_submit").find("#confirm_at").val(at);

        var myModal = new bootstrap.Modal(document.getElementById('confirmModal'), {});
        myModal.show();

        event.preventDefault();
    }


    ok(event) {
        console.log("confirm clicked");
        $('#confirmModal').modal('hide');
        let formName = $('#confirmModal #submitForm').val();
        console.log(`formName: ${formName}`);
        if ( formName ) {
            event.preventDefault();
            $(formName).submit();
        }
    }


    copy(event) {
        console.log(event.target);
        // Get the text field
        let target = $(event.target).data('target');
        let notify_span = $(event.target).data('notify');

        console.log(target);

        let copyText = $(target)[0];
        let notifyText = $(notify_span)[0];

         // Copy the text inside the text field
        navigator.clipboard.writeText(copyText.innerText);
        console.log(copyText.innerText);

        // Alert the copied text
        console.log("Copied the text: " + copyText.innerText);
        // $(copyText).css({'color': 'blue', 'font-weight': '500'});
        $(copyText).animate({color:'blue', 'font-size': '110%'}, 1000);
        $(notifyText).text(`Copied ${copyText.innerHTML}`);
    }

    popup_status(event) {
        $('#alertPopupModal').modal('show');
    }

}


