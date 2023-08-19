import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    
  }

  setPersona(event) {    
    // Make the call
    console.log("setPersona called");
    let form = $("#persona_form");
    let submit = form.find("input[type='submit']");
    submit.click();
  }


};
