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
            if (selected_field.length === 0) { selected_field = $(this.element).find("select").first(); }
            selected_value = $(selected_field).val();
        }

        // Locate the surrounding form group and the associated "Other" field within it
        const form_group = $(selected_field).closest(".form-group");
        const other_field = form_group.find(this.otherIdValue);

        // Get and trim the value from the "Other" input field
        const rawOther = other_field.val();
        const other_value = (typeof rawOther === "string" ? rawOther.trim() : "");

        // Decide whether to show the "Other" input field based on the selected value
        if ((selected_value != null && String(selected_value).length > 0) || other_field.length > 0) {
            // compare TRIMMED option values to avoid space mismatches
            const optionValues = $(selected_field)
            .find("option")
            .map(function () { return (this.value || "").trim(); })
            .get();

            const valueIsOther = selected_value === "Other";
            // only treat typed value as "not in options" when the select is blank
            const valueNotInOptions = (!selected_value || String(selected_value).length === 0) &&
                                    other_value.length > 0 &&
                                    !optionValues.includes(other_value);

        if (valueIsOther || valueNotInOptions) {
        // remove the select when using the "Other" input
        $(selected_field).remove();
        other_field.prop("disabled", false).show().removeAttr("hidden");
        } else {
        // selecting a normal option → ensure text input is fully hidden/disabled
        other_field.hide().prop("disabled", true).attr("hidden", true);
        }
    }
    }
}
