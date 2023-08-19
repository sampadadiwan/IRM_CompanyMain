import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("fund_formula connect");
    this.ruleTypeChanged();
  }

  ruleTypeChanged()  {
    let val = $("#fund_formula_rule_type").val();
    console.log(`ruleTypeChanged ${val}`);
    $(".explanation").hide();
    $(`#${val}`).show();
  }

};
