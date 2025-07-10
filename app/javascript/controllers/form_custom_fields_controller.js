import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    static cfe;

  connect() {
    console.log("form_custom_fields_controller connect");

    // Attach an 'input' event listener to all elements with the class 'custom_field'
    // When the input value changes, the 'valueChanged' function is called with the event target as an argument
    $( ".custom_field" ).on("input", (event)=>{
        this.valueChanged(event.target);
    });

    // Iterate over each element with the class 'custom_field'
    // If the value of the element is not an empty string, call the 'valueChanged' function with the element as an argument
    $( ".custom_field" ).each((idx, elem) => {
        if($(elem).val() !== null && $(elem).val() !== "") {
            this.valueChanged(elem);
        }
    });

  }

  initialize() {
    // Hide all elements with the class 'fcf.conditional.hide'
    $("body").find(".fcf.conditional").hide();
    // Show all elements with the class 'fcf.conditional.show'
    // $("body").find(".fcf.conditional.show").show();
    // Initialize subcategories based on the selected category
    const categoryDropdown = this.element.querySelector(
      "select[id$='_investor_category']"
    );

    if (categoryDropdown) {
      this.updateSubcategories(categoryDropdown.value, categoryDropdown);
    }
  }

  investor_category_changed(event) {
    this.updateSubcategories(event.target.value, event.target);
  }

  // This function is called when the value of an element with the class 'custom_field' changes
  valueChanged(changed_elem) {

    // Get the id and value of the changed element
    let fcf_change_id = $( changed_elem ).attr("id");
    console.log(`fcf_change_id = ${fcf_change_id}`);
    let required_on_show = $( changed_elem ).attr("required");
    let val = $( changed_elem ).val().toString();
    console.log(`required_on_show = ${required_on_show}, ${val}`);
    let fcf_change_value = val.toLowerCase();
    // console.log( `Input ${fcf_change_id} changed to ${fcf_change_value}` );

    // Iterate over each element with the class 'fcf.conditional' which is dependent on fcf_change_id
    $("body").find(`.fcf.conditional.${fcf_change_id}`).each((idx, elem) => {
        // We have a field that is dependent on the changed field
        // We have to use the criteria eq, not eq, etc. to match the value
        // We have the state show, hide
        let criteria = $(elem).attr("data-match-criteria")
        let data_match_value = $(elem).attr("data-match-value").toLowerCase();
        let matched = null;
        if (fcf_change_value && criteria == "contains") {
            matched = (fcf_change_value.includes(data_match_value) || data_match_value.includes(fcf_change_value)) ? "matched" : "not-matched";
        } else if (criteria == "gt" || criteria == "lt" || criteria == "gte" || criteria == "lte") {
            const num_fcf_change_value = parseFloat(fcf_change_value);
            const num_data_match_value = parseFloat(data_match_value);

            if (!isNaN(num_fcf_change_value) && !isNaN(num_data_match_value)) {
                if (criteria == "gt") {
                    matched = num_fcf_change_value > num_data_match_value ? "matched" : "not-matched";
                } else if (criteria == "lt") {
                    matched = num_fcf_change_value < num_data_match_value ? "matched" : "not-matched";
                } else if (criteria == "gte") {
                    matched = num_fcf_change_value >= num_data_match_value ? "matched" : "not-matched";
                } else { // criteria == "lte"
                    matched = num_fcf_change_value <= num_data_match_value ? "matched" : "not-matched";
                }
            } else {
                matched = "not-matched"; // Cannot compare non-numeric values
            }
        }
        else {
            matched = data_match_value == fcf_change_value ? "matched" : "not-matched";
        }

        // Get the initial state of the element
        let initial_state = $(elem).hasClass("show") ? "show" : "hide";
        // Create a switch value to determine if the element should be shown or hidden
        let switch_val = `${matched}-${criteria}-${initial_state}`;

        console.log(`switch_val = ${switch_val}`)
        switch( switch_val ) {
            case "matched-eq-show":
            case "matched-contains-show":
            case "not-matched-not_eq-show":
            case "matched-gt-show":
            case "matched-lt-show":
            case "matched-gte-show":
            case "matched-lte-show":
                $(elem).show();
                if (required_on_show) {
                    this.require_form_elements(elem);
                }
                break;
            default:
                $(elem).hide();
                this.clear_form_elements(elem);
                break;
        }
    });
  }


  // This function is called when the conditional element is hidden.
  // It clears the form elements in the hidden element
  clear_form_elements(elem) {
    let has_file_input = $(elem).find(':file').length > 0;
    if (has_file_input) {
      // File inputs need to be handled differently
      // We should not clear the other fields associated with the file like name, send_email etc
      // see _file.html.erb custom field
      $(elem).find(':input').each(function() {
        switch(this.type) {
            case 'file':
                // jQuery(this).val('');
                break;
        }
        // Remove the required attribute from the form element
        $(this).removeAttr('required');
      });
    } else {
      $(elem).find(':input').each(function() {
        switch(this.type) {
            case 'password':
            case 'text':
            case 'textarea':
            case 'file':
            case 'select-one':
            case 'select-multiple':
            case 'date':
            case 'number':
            case 'tel':
            case 'email':
                jQuery(this).val('');
                break;
            case 'checkbox':
            case 'radio':
                this.checked = false;
                break;
        }
        // Remove the required attribute from the form element
        $(this).removeAttr('required');
      });
    }
  }

  require_form_elements(elem) {
    let has_file_input = $(elem).find(':file').length > 0;
    if(has_file_input) {
      // File inputs need to be handled differently
      // We should not require other fields associated with the file like owner_tag, send_email etc
      // see _file.html.erb custom field
      let req = false;
      console.log("File input found");
      $(elem).find(':file').each(function() {
        let field_id = $(this).attr('id');
        if(field_id) {
          // Sometimes file has already been uploaded, so dont require it
          let req = $(`#document_required_${this.id}`).val();
          if(req == "true") {
            console.log(`Adding required to ${this.type} ${field_id}`);
            $(this).attr('required', 'required');
          }
        }
      });
      return;
    } else {
      $(elem).find(':input').each(function() {
        let required = $(this).parent(".form-group").attr('data-mandatory');
        console.log(`required = ${required}`);
        if (required == "true") {
          console.log(`Adding required to ${this.type} ${this.id}`);
          $(this).attr('required', 'required');
        }
      });
    }
  }

  updateSubcategories(selectedCategory, categoryElement) {
    const SEBI_INVESTOR_SUB_CATEGORIES_MAPPING = {
      Internal: [
        "Sponsor",
        "Manager",
        "Directors/Partners/Employees of Sponsor",
        "Directors/Partners/Employees of Manager",
        "Employee Benefit Trust of Manager",
      ],
      Domestic: [
        "Banks",
        "NBFCs",
        "Insurance Companies",
        "Pension Funds",
        "Provident Funds",
        "AIFs",
        "Other Corporates",
        "Resident Individuals",
        "Non-Corporate (other than Trusts)",
        "Trusts",
      ],
      Foreign: ["FPIs", "FVCIs", "NRIs", "Foreign Others"],
      Other: [
        "Domestic Developmental Agencies/Government Agencies",
        "Others",
      ],
    };

    // Find the subcategory dropdown within the same form
    const formElement = categoryElement.closest("form");
    const subCategoryDropdown = formElement.querySelector(
      "select[id$='_investor_sub_category']"
    );

    if (!subCategoryDropdown) {
      console.error("Subcategory dropdown not found");
      return;
    }

    // Store the existing selected value
    const existingValue = subCategoryDropdown.value;

    // Get the subcategories for the selected category
    const subCategories =
      SEBI_INVESTOR_SUB_CATEGORIES_MAPPING[selectedCategory] || [];

    // Clear the current subcategories
    subCategoryDropdown.innerHTML = "";

    // Populate the dropdown with new subcategories
    subCategories.forEach((subCategory) => {
      const option = document.createElement("option");
      option.value = subCategory;
      option.textContent = subCategory;

      // Set as selected if it matches the existing value
      if (subCategory === existingValue) {
        option.selected = true;
      }

      subCategoryDropdown.appendChild(option);
    });
  }

}


