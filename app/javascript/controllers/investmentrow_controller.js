import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    $(".preferred_conversion_group").hide();
  }

  onChange(event) {
    console.log("onChange");
    console.log("change");

    let selected = $(event.target).val();

    switch (selected) {
      case "Preferred":
        // hide category & disable
        $(event.target).closest(".form-row").find(".preferred_conversion_group").show();       
        break;
      default:
        // hide category & disable
        $(event.target).closest(".form-row").find(".preferred_conversion_group").hide();
        break;
    }
  }

}
