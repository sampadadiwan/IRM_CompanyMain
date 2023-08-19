import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    this.onChange();
  }

  onChange() {
    console.log("onChange");
    let selected = $(".commitment_type").val();

    switch (selected) {
      case "Pool":
        // hide category & disable
        $(".co-invest").hide();       
        $(".pool").show();       
        break;
      case "CoInvest":
        // hide category & disable
        $(".co-invest").show();
        $(".pool").hide();
        break;
    }
  }

};
