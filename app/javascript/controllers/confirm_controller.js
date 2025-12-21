import { Controller } from "@hotwired/stimulus"

/**
 * ConfirmController manages the global confirmation modal used throughout the application.
 * It intercepts click events on buttons/links, populates a shared modal with dynamic content,
 * and handles the submission of the associated form upon user confirmation.
 *
 * @example
 * <button data-action="click->confirm#popup"
 *         data-title="Confirm Delete"
 *         data-msg="Are you sure you want to delete this?"
 *         data-method="delete"
 *         data-notification="yes"
 *         data-reversible="no"
 *         data-docs="https://example.com/docs"
 *         data-other-info="Additional context here">
 *   Delete
 * </button>
 */
export default class extends Controller {

    connect() {
        console.log("confirm connect");
        // Automatically show alert popup if present on page load
        if( $("#alertPopupModal").length ) {
            this.popup_status();
        }
    }

    /**
     * Triggered when a confirmation-required button is clicked.
     * Populates and opens the #confirmModal.
     *
     * @param {Event} event - The click event
     */
    popup(event) {
        let btn = $(event.target);

        // Extract basic modal content from data attributes
        let title = event.target.dataset.title || "Are you sure?";
        let method = event.target.dataset.method || "delete";
        let msg = event.target.dataset.msg || "This will permanently delete this item. Proceed?" ;
        let submitForm = event.target.dataset.submitForm;

        // Extract optional additional details
        let notification = event.target.dataset.notification;
        let reversible = event.target.dataset.reversible;
        let docs = event.target.dataset.docs;
        let otherInfo = event.target.dataset.otherInfo;

        console.log(`btn.dataset.modalId: ${event.target.dataset.modalId}`);

        // Find the form containing the clicked button to replicate its action/token
        this.deleteForm = event.target.closest("form");

        // Update basic modal content
        $('#confirmModal #msg').html(msg);
        $('#confirmModal #title').text(title);
        $('#confirmModal #method').val(method);
        $('#confirmModal #submitForm').val(submitForm);

        // Reset and populate additional info sections
        let hasAdditionalInfo = false;
        const detailsContainer = $('#confirmModal #confirm_details');

        // Handle Notification status (Yes/No with icons)
        if (notification) {
            hasAdditionalInfo = true;
            $('#confirmModal #confirm_notification').show();
            let icon = notification === 'yes' ? '<i class="ti ti-bell-check text-success"></i> Yes' : '<i class="ti ti-bell-off text-danger"></i> No';
            $('#confirmModal #confirm_notification_icon').html(icon);
        } else {
            $('#confirmModal #confirm_notification').hide();
        }

        // Handle Reversibility status (Yes/No with icons)
        if (reversible) {
            hasAdditionalInfo = true;
            $('#confirmModal #confirm_reversible').show();
            let icon = reversible === 'yes' ? '<i class="ti ti-refresh text-success"></i> Yes' : '<i class="ti ti-alert-triangle text-danger"></i> No';
            $('#confirmModal #confirm_reversible_icon').html(icon);
        } else {
            $('#confirmModal #confirm_reversible').hide();
        }

        // Handle Documentation link
        if (docs) {
            hasAdditionalInfo = true;
            $('#confirmModal #confirm_docs').show();
            $('#confirmModal #confirm_docs_link').attr('href', docs);
        } else {
            $('#confirmModal #confirm_docs').hide();
        }

        // Handle generic Other Info text
        if (otherInfo) {
            hasAdditionalInfo = true;
            $('#confirmModal #confirm_other_info').show();
            $('#confirmModal #confirm_other_info_text').text(otherInfo);
        } else {
            $('#confirmModal #confirm_other_info').hide();
        }

        // Show/hide the entire details section if any additional info exists
        if (hasAdditionalInfo) {
            detailsContainer.show();
        } else {
            detailsContainer.hide();
        }

        // Configure the modal's hidden form to match the triggering button's form
        $("#confirm_submit").attr("action", this.deleteForm.action);

        // Handle Turbo configuration
        $("#confirm_submit").attr("data-turbo", true);
        if(btn.attr("data-turbo") == "false") {
            $("#confirm_submit").attr("data-turbo", false);
        }

        // Sync the CSRF authenticity token
        let at = $(this.deleteForm).find('input[name="authenticity_token"]').val();
        $("#confirm_submit").find("#confirm_at").val(at);

        // Initialize and display the Bootstrap modal
        var myModal = new bootstrap.Modal(document.getElementById('confirmModal'), {});
        myModal.show();

        event.preventDefault();
    }


    /**
     * Triggered when the "Proceed" button in the modal is clicked.
     * Submits the form or triggers a specific form submission if defined.
     *
     * @param {Event} event - The click event
     */
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


    /**
     * Utility method to copy text to clipboard and show a notification.
     *
     * @param {Event} event - The click event
     */
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

        // Alert the copied text and animate
        console.log("Copied the text: " + copyText.innerText);
        $(copyText).animate({color:'blue', 'font-size': '110%'}, 1000);
        $(notifyText).text(`Copied ${copyText.innerHTML}`);
    }

    /**
     * Directly show the alert popup modal.
     */
    popup_status(event) {
        $('#alertPopupModal').modal('show');
    }

}
