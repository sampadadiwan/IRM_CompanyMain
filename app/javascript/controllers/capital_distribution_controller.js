import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("capital_distributions connect");
    this.distribution_on_changed();
  }

  distribution_on_changed() {
    let distribution_on = $("#capital_distribution_distribution_on").val()

    if (distribution_on === "Upload") {
      $("#capital_distributions_gross_amount").hide();
      $("#capital_distributions_cost_of_investment").hide();
      $("#capital_distributions_reinvestment").hide();
    } else {
      $("#capital_distributions_gross_amount").show();
      $("#capital_distributions_cost_of_investment").show();
      $("#capital_distributions_reinvestment").show();
    }
  }
}