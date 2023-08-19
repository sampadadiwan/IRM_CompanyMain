import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    
  }

  format(e) {
    const input = e.target;
    const formatter = new Intl.NumberFormat("en-US");
    let span = $(e.target).closest(".form-group").find(".formatted_currency");
    if(input.value) {
        span.text(formatter.format(input.value));
    } else {
        span.text("");
    }

  }


};
