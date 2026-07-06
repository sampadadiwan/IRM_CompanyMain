import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {

  connect() {
    // this controller is used in  Portfolio/Scenario Investment form and access rights form
    // Below condition checks if instrument id is populated on connect and if so, it dispatches a change event
    // this instrument id check does not affect access rights form
    this.element.querySelectorAll("select[data-param='investment_instrument_id']").forEach(select => {
      if (select.value) {
        select.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })
  }

  change(event) {
    if(event.target.selectedOptions[0].value) {

      let target = $(event.target).data("target");
      let url = $(event.target).data("url");
      let param = $(event.target).data("param");

      let baseUrl = url.split("?")[0];
      let params = new URLSearchParams(url.split("?")[1]);

      console.log(`target: ${target}`);
      console.log(`url: ${url}`);
      console.log(`param: ${param}`);

      params.append(param, event.target.selectedOptions[0].value);
      params.append("target", target);

      get(`${baseUrl}?${params}`, {
        responseKind: "turbo-stream"
      });
    }
  }
}
