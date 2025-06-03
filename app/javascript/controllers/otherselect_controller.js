import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    static values = {
        // ID selector for the <select> element being watched
        selectId: String, 
        // ID selector for the "Other" text input field
        otherId: String
    }

    connect() {
        // Fallback to default "Other" input field selector if none provided
        if (!this.otherIdValue) {
            this.otherIdValue = "#other_name";
        }

        console.log(`otherIdValue = ${this.otherIdValue}`);

        // Initial check to see if the "Other" input should be shown
        this.checkOtherName();
    }

    checkOtherName(event) {
        let selected_value = "";
        let selected_field = null;

        if (event) {
            // If triggered by a change event, get the selected element and value from the event
            selected_field = event.target;
            selected_value = event.target.value;
        } else {
            // If not triggered by an event, fetch the select field and value using the selector
            selected_field = $(this.selectIdValue);
            selected_value = $(this.selectIdValue).val();
        }

        // Locate the surrounding form group and the associated "Other" field within it
        let form_group = $(selected_field).closest(".form-group");
        let other_field = form_group.find(this.otherIdValue);

        // Get trimmed value from the "Other" field
        let other_value = $(other_field).val()?.trim();

        console.log(`selected_value = ${selected_value}`);
        console.log(`other_value = ${other_value}`);

        // Proceed only if there's a selected value or the "Other" field exists
        if ((selected_value != null && selected_value.length > 0) || other_field.length > 0) {

            // Extract all valid option values from the select field
            let optionValues = $(selected_field)
                .find("option")
                .map(function () {
                    return this.value;
                })
                .get();

            // Determine if selected value is explicitly "Other"
            let valueIsOther = selected_value === "Other";

            // Determine if the "Other" input value is not part of the options
            let valueNotInOptions = other_value.length > 0 && !optionValues.includes(other_value);

            if (valueIsOther || valueNotInOptions) {
                // Show and enable the "Other" input if conditions met
                $(selected_field).remove(); // Optional: removes the original select field
                $(other_field).prop("disabled", "")
                $(other_field).show();
                $(other_field).removeAttr("hidden");
            } else {
                // Otherwise hide the "Other" input
                $(other_field).hide();
            }
        }
    }
}
