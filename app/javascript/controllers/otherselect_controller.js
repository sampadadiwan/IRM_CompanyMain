import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    static values = {
        selectId: String, // Which select id are we targeting
        otherId: String
    }

  connect() {    
    if(!this.otherIdValue) {
      this.otherIdValue = "#other_name";
    }
    console.log(`otherIdValue = ${this.otherIdValue}`);
    this.checkOtherName();
    
  }

  checkOtherName(event) {
    let selected_value = "";
    let selected_field = null;
    if(event){            
      selected_field = event.target;
      selected_value = event.target.value;
    } else {      
      selected_field = $(this.selectIdValue);
      selected_value = $(this.selectIdValue).val();
    }

    console.log(`selected_value = ${selected_value}`);
    

    if(selected_value != null && selected_value.length > 0) {

      let form_group = $(event.target).closest(".form-group");
      let other_field = form_group.find(this.otherIdValue);
      console.log(selected_field);
      console.log(other_field);

      console.log(other_field);
      if (selected_value == "Other") {
        $(selected_field).remove();
        $(other_field).prop("disabled", "")
        $(other_field).show();
        $(other_field).removeAttr("hidden");
      } else {
        $(other_field).hide();
      }
    }
  }

}
