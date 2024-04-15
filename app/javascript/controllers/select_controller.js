import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  
  connect() {
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