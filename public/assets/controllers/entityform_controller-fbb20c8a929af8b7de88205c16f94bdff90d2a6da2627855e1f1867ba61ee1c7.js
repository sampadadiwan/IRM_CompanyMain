import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    $( document ).on('turbo:render', function() {
        console.log("EntityFormController");

        if ($("#entity_entity_type").val() == "Investor") {
          $("#entity_founded_group").toggle();
          $("#entity_funding_amount").toggle();
          $("#entity_funding_unit").toggle();
          console.log("EntityFormController: toggled");
        }
      
        $("#entity_entity_type").on("change", function(){
            console.log("EntityFormController: change");
            $("#entity_founded_group").toggle();
            $("#entity_funding_amount").toggle();
            $("#entity_funding_unit").toggle();
        });

    });
  }
};
