import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("investor search connect");


        $("#investor_investor_name").autocomplete({
            source: "/entities/search.json",
            minLength: 3,
            response: function (event, ui) {
                console.log(ui.content);
                if (ui.content.length == 0) {
                    // alert("No results found for this investor name");
                    // $("#investor_investor_name").val("");
                    $("#investor_investor_entity_id").val("");
                }
            },
            select: function (event, ui) {
                ui.item.label = ui.item.investor_name;
                // $("#investor_investor_entity_id").val(ui.item.id);
                $("#investor_pan").val(ui.item.pan);
            }
        });


    }


}


