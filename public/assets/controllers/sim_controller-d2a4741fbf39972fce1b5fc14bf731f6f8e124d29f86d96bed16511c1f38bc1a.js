import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  count = 1;
  connect() {
    console.log("sim controller connected");
    $("#add_sim")[0].click();
  }

  updateSim(e) {
    this.count += 1;
    console.log(this.count);
    console.log($("#add_sim").attr("data-turbo-frame"));
    setTimeout(this.updateSimCount.bind(null, this.count), 50);   
  }

  updateSimCount(count) {
    $("#add_sim").attr("data-turbo-frame", `new_simulator_${count}`);
    let loc = "/aggregate_investments/new_simulator";
    console.log(`${loc}?count=${count}`);
    $("#add_sim").attr("href", `${loc}?count=${count}`);

    if(count == 7) {
      $("#add_sim").remove();
    }

  }

};
