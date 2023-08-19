import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    this.onChange(null);
    console.log("ESOP javascript loaded");
  }

  onChange(event) {
    console.log("onChange");
    let selected = $("#holding_investment_instrument").val();
    switch (selected) {
      case "Options":
        $(".funding_round_group").hide();
        $(".option_pool_group").show();
        break;
      default:
        $(".funding_round_group").show();
        $(".option_pool_group").hide();
        break;
    }
  }

};
