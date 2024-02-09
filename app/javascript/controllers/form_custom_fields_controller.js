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
        if($(elem).val() != "") {
            this.valueChanged(elem);
        }
    });

  }
 
  initialize() {
    // Hide all elements with the class 'fcf.conditional.hide'
    $("body").find(".fcf.conditional.hide").hide();
    // Show all elements with the class 'fcf.conditional.show'
    $("body").find(".fcf.conditional.show").show();
  }

  // This function is called when the value of an element with the class 'custom_field' changes
  valueChanged(changed_elem) {

    // Get the id and value of the changed element
    let fcf_change_id = $( changed_elem ).attr("id");
    let fcf_change_value = $( changed_elem ).val().toLowerCase();
    // console.log( `Input ${fcf_change_id} changed to ${fcf_change_value}` );
    
    // Iterate over each element with the class 'fcf.conditional' which is dependent on fcf_change_id
    $("body").find(`.fcf.conditional.${fcf_change_id}`).each((idx, elem) => {
        // We have a field that is dependent on the changed field
        // We have to use the criteria eq, not eq, etc. to match the value
        // We have the state show, hide 
        let criteria = $(elem).attr("data-match-criteria")
        let data_match_value = $(elem).attr("data-match-value").toLowerCase();
        let matched = null;
        if(fcf_change_value && criteria == "contains") {
            matched = (fcf_change_value.includes(data_match_value) || data_match_value.includes(fcf_change_value)) ? "matched" : "not-matched";
        } else {
            matched = data_match_value == fcf_change_value ? "matched" : "not-matched";
        }
                
        // Get the initial state of the element
        let initial_state = $(elem).hasClass("show") ? "show" : "hide";
        // Create a switch value to determine if the element should be shown or hidden
        let switch_val = `${matched}-${criteria}-${initial_state}`;

        console.log(`switch_val = ${switch_val}`)
        switch( switch_val ) {
            case "matched-eq-hide": case "matched-contains-hide": case "not-matched-eq-show": case "not-matched-contains-show": case "not-matched-not_eq-hide": case "matched-not_eq-show":
                $(elem).show();
                break;
            case "matched-eq-show": case "matched-contains-show": case "not-matched-eq-hide": case "not-matched-contains-hide": case "not-matched-eq-hide": case "matched-not_eq-hide":
                $(elem).hide();
                this.clear_form_elements(elem);
                break;
            default:
                console.log(`No match for ${switch_val}`);
        }
    });   
  }


  // This function is called when the conditional element is hidden. 
  // It clears the form elements in the hidden element
  clear_form_elements(elem) {
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
    });
  }

}


