import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    
  }

  setPersona(event) {    
    // Make the call
    console.log("setPersona called");
    let form = $(event.target).closest("form");
    let submit = form.find("input[type='submit']");
    if ($("#investor_advisor").val().length == 0) {
      console.log("investor_advisor is empty");
    }
    submit.click();
  }


}
