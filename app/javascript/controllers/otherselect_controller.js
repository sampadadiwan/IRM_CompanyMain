import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    static values = {
        selectId: String, // Which select id are we targeting
        otherId: String
    }

  connect() {    
    this.checkOtherName();
  }

  checkOtherName(event) {
    console.log($(this.selectIdValue).val());

    if($(this.selectIdValue).length > 0) {
      let selected = $(this.selectIdValue).val();
      console.log(`other_name = ${$("#other_name").val().length}`);

      if (selected == "Other" || $("#other_name").val().length > 0) {
        $(this.selectIdValue).remove();
        $("#other_name").prop("disabled", "")
        $("#other_name").show();
      } else {
        $("#other_name").hide();
      }
    }
  }

}
