import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    
  }

  submit(event) {
    // Make the call
    let form = $("#remittance_filter");

    // let submit = form.find("input[type='submit']");
    // submit.click();
    event.target.form.requestSubmit();

  }


}
