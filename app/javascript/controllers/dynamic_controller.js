import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    this.init();
    $('.select2-multiple').select2();
  }

  init() {
    console.log("Dynamic loaded");
  }

  close(event) {
    console.log("closeForm");
    $(".dynamic_form").remove();
  }
}
