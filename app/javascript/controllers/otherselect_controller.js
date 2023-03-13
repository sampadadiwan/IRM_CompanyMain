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
    console.log($(this.selectIdValue).val());

    if($(this.selectIdValue).length > 0) {
      let selected = $(this.selectIdValue).val();
      console.log(`other_name = ${$(this.otherIdValue).val().length}`);

      if (selected == "Other" || $(this.otherIdValue).val().length > 0) {
        $(this.selectIdValue).remove();
        $(this.otherIdValue).prop("disabled", "")
        $(this.otherIdValue).show();
      } else {
        $(this.otherIdValue).hide();
      }
    }
  }

}
