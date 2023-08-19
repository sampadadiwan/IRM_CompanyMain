import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {

  }

  close(event) {
    console.log("closeForm");
    $(".dynamic_form").remove();
  }
};
