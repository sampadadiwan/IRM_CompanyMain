import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {

  }

  setPersona(event) {
    // Make the call
    console.log("setPersona called");
    let form = $(event.target).closest("form");
    let submit = form.find("input[type='submit']");
    submit.click();
  }


  setRegion(event) {
    // Make the call
    console.log("setRegion called");
    let form = $(event.target).closest("form");
    let submit = form.find("input[type='submit']");
    submit.click();
  }


}
