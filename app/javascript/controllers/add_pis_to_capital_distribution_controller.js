// import { Controller } from "@hotwired/stimulus"
import ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {

  connect() {
    console.log("add_pis_to_capital_distribution connected");

    $(".select2").on('select2:select', function () {
      let event = new Event('change', { bubbles: true }) // fire a native event
      this.dispatchEvent(event);
    });
  }

  add_pis(event) {
    console.log("add_pis called");

    // Get the selected portfolio investment IDs from the input field
    let portfolio_investment_ids = $("#capital_distribution_portfolio_investment_ids").val();
    let fund_id = $("#capital_distribution_fund_id").val();
    let entity_id = $("#capital_distribution_entity_id").val();

    // Call the server to add the selected portfolio investments to the capital distribution
    let url = `/capital_distributions/add_pis_to_capital_distribution?entity_id=${entity_id}&fund_id=${fund_id}&portfolio_investment_ids=${portfolio_investment_ids}`;
    console.log(url);

    // Fetch the response from the server
    fetch(url, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html"
      },
      credentials: "include" // if you need to include cookies
    })
    .then(response => response.text())
    .then(html => {
      Turbo.renderStreamMessage(html);
    });
  }


}
